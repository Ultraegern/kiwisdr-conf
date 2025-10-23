use actix_web::{get, post, web, App, HttpResponse, HttpServer, Responder};
use serde::{Serialize, Deserialize};
use serde_json::json;
use tokio::io::{AsyncBufReadExt, BufReader};
use std::collections::VecDeque;
use std::process::Stdio;
use std::sync::Arc;
use std::fmt;
use tokio::process::Child;
use tokio::sync::Mutex;

#[derive(Clone, Serialize, Deserialize)]
struct Log {
    timestamp: u64, // Unix
    data: String
}

type Logs = VecDeque<Log>;

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum RecordingType {
    PNG,
    IQ
}

impl fmt::Display for RecordingType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RecordingType::PNG => write!(f, "Png"),
            RecordingType::IQ => write!(f, "Iq"),
        }
    }
}

#[derive(Deserialize)]
struct RecorderSettings {
    rec_type: RecordingType,
    frequency: u32, // Hz
    #[serde(default)] // defaults zoom to 0 if not provided
    zoom: u8,
    autostop: u16 // Sec, O if off
}

impl fmt::Display for RecorderSettings {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Type: {}, Frequency: {} Hz, {}Autostop: {}",
            self.rec_type,
            self.frequency,
            match self.rec_type {
                RecordingType::PNG => format!("Zoom: {}", self.zoom),
                RecordingType::IQ => "".to_string()
            },
            if self.autostop == 0 { String::from("Off") } else { format!("{} sec", self.autostop.to_string()) }
        )
    }
}

type ArtixRecorderSettings = web::Json<RecorderSettings>;

struct RecorderState {
    running: bool,
    process: Option<Child>,
    started_at: Option<u64>,
    logs: Logs
}

type SharedRecorder = Arc<Mutex<RecorderState>>;
type ArtixSharedRecorder = actix_web::web::Data<SharedRecorder>;

async fn read_output(pipe: impl tokio::io::AsyncRead + Unpin, recorder: SharedRecorder, pipe_tag: &str, responsible_for_exit: bool) {
    let reader = BufReader::new(pipe);
    let mut lines = reader.lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let mut state = recorder.lock().await;
        state.logs.push_back(Log {
            timestamp: chrono::Utc::now().timestamp() as u64, 
            data: format!("<{}> {}", pipe_tag, line)
        });
        if state.logs.len() > 997 {
            state.logs.pop_front();
        }

    }
    if responsible_for_exit {
        let mut state = recorder.lock().await;
        state.running = false;
        state.started_at = None;
        state.logs.push_back(Log {
            timestamp: chrono::Utc::now().timestamp() as u64, 
            data: "<Exited>".to_string()
        });
    }
}

fn to_scientific(num: u32) -> String {
    if num == 0{
        return "0e0".to_string();
    }
    let exponent = (num as f64).log10().floor() as u32;
    let mantissa = num as f64 / 10f64.powi(exponent as i32);
    
    let mantissa_str = format!("{:.3}", mantissa)
        .trim_end_matches('0')
        .trim_end_matches('.')
        .replace('.', "d");

    return format!("{}e{}", mantissa_str, exponent);
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port: u16 = 5004;

    let shared_recorder: SharedRecorder = Arc::new(Mutex::new(RecorderState {
        running: false,
        process: None,
        started_at: None,
        logs: VecDeque::new(),
    }));

    println!("Starting server on port {}", port);
    HttpServer::new(move || {
        App::new()
            .app_data(actix_web::web::Data::new(shared_recorder.clone()))
            .service(status)
            .service(start_recorder)
            .service(stop_recorder)
            .service(recorder_status)
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}

#[get("/api/status")]
async fn status() -> impl Responder {
    HttpResponse::Ok().body(
        "Api is Online"
    )
}

#[get["/api/recorder/status"]]
async fn recorder_status(recorder_state: ArtixSharedRecorder) -> impl Responder {
    const MAX_LOG_LENGTH: usize = 200;
    const LOG_COUNT: usize = 20;

    let state = recorder_state.lock().await;
    let is_recording = state.running;
    let started_at = state.started_at;
    let logs = state.logs.clone();
    drop(state);

    let last_logs: Vec<Log> = logs
        .iter()
        .rev() // start from the newest
        .take(LOG_COUNT)
        .map(|log| {
            let truncated_data = if log.data.len() > MAX_LOG_LENGTH {
                format!("{}...", &log.data[..MAX_LOG_LENGTH])
            } else {
                log.data.clone()
            };

            Log {
                timestamp: log.timestamp,
                data: truncated_data,
            }
        })
        .collect();

    let message: String = match is_recording {
        true => "Recording",
        false => "Not Recording"
    }.to_string();

    return HttpResponse::Ok().json(json!({ 
        "message": message,
        "recording": is_recording,
        "started_at": started_at,
        "last_logs": last_logs
    }))
}

#[post("/api/recorder/start")]
async fn start_recorder(settings_raw: ArtixRecorderSettings, recorder_state: ArtixSharedRecorder) -> impl Responder {
    let settings = settings_raw.into_inner();
    { // Exit if already running
        let check_state = recorder_state.lock().await;
        let is_recorder_running = check_state.running;
        let recorder_start_time = check_state.started_at;
        drop(check_state);

        if is_recorder_running{
            return HttpResponse::BadRequest().json(json!({ 
                "message": "Recorder is already running",
                "recording": true,
                "started_at": recorder_start_time
            }));
        }
    }
    { // Check that zoom and freq are valid
        if settings.zoom > 31 { // Prevent bitshifting a u32 by 32 bits
            return HttpResponse::BadRequest().json(json!({ 
                "message": "Zoom to high",
                "recording": false,
                "started_at": Option::<u64>::None
            }));
        }

        const MIN_FREQ: u32 = 0;
        const MAX_FREQ: u32 = 30_000_000;
        let zoom = settings.zoom as u32;
        let center_freq = settings.frequency;

        let bandwidth = (MAX_FREQ - MIN_FREQ) / (1 << zoom); // "(1 << zoom)" bitshift is same as "(2^zoom)"
        let selection_freq_max = center_freq.saturating_add(bandwidth / 2); // Saturating add/sub to avoid integer overflow
        let selection_freq_min = center_freq.saturating_sub(bandwidth / 2);

        if selection_freq_max > MAX_FREQ {
            return HttpResponse::BadRequest().json(json!({ 
                "message": "The selected frequency range exceeds the maximum frequency",
                "recording": false,
                "started_at": Option::<u64>::None
            }));
        }
        if selection_freq_min < MIN_FREQ {
            return HttpResponse::BadRequest().json(json!({ 
                "message": "The selected frequency range exceeds the minimum frequency",
                "recording": false,
                "started_at": Option::<u64>::None
            }));
        }
    }
    
    let filename_common = format!("{}_Fq{}", chrono::Utc::now().format("%Y-%m-%d_%H-%M-%S_UTC").to_string(), to_scientific(settings.frequency));
    let filename_png = format!("{}_Zm{}", filename_common, settings.zoom.to_string());
    let filename_iq = format!("{}_Bw1d2e4", filename_common);

    let mut args: Vec<String>  = match settings.rec_type {
        RecordingType::PNG => vec![
            "-s".to_string(), "127.0.0.1".to_string(),
            "-p".to_string(), "8073".to_string(),
            format!("--freq={:#.3}", (settings.frequency as f64 / 1000.0)),
            "-d".to_string(), "/var/recorder/recorded-files/".to_string(),
            "--filename=KiwiRec".to_string(),
            format!("--station={}", filename_png),

            "--wf".to_string(), 
            "--wf-png".to_string(), 
            "--speed=4".to_string(), 
            "--modulation=am".to_string(), 
            format!("--zoom={}", settings.zoom.to_string())],
        RecordingType::IQ => vec![
            "-s".to_string(), "127.0.0.1".to_string(),
            "-p".to_string(), "8073".to_string(),
            format!("--freq={:#.3}", (settings.frequency as f64 / 1000.0)),
            "-d".to_string(), "/var/recorder/recorded-files/".to_string(),
            "--filename=KiwiRec".to_string(),
            format!("--station={}", filename_iq),

            "--kiwi-wav".to_string(), 
            "--modulation=iq".to_string()]
    };

    if settings.autostop != 0 {
        args.push(format!("--time-limit={}", settings.autostop));
    }

    let mut child: Child = tokio::process::Command::new("python3")
        .arg("kiwirecorder.py")
        .args(args)
        .current_dir("/usr/local/src/kiwiclient/")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("Failed to start recorder process");

    if let Some(stdout) = child.stdout.take() {
        tokio::spawn(read_output(stdout, recorder_state.get_ref().clone(), "STDOUT", true));
    }
    if let Some(stderr) = child.stderr.take() {
       tokio::spawn(read_output(stderr, recorder_state.get_ref().clone(), "STDERR", false));
    }
    
    let now = chrono::Utc::now().timestamp() as u64;
    let started_at_log = Log {
        timestamp: now,
        data: "<Started>".to_string()
    };
    let started_settings_log = Log {
        timestamp: now,
        data: format!("<Settings>  {}", settings)
    };
    let mut state = recorder_state.lock().await;
    state.process = Some(child);
    state.running = true;
    state.started_at = Some(now);
    state.logs.push_back(started_at_log);
    state.logs.push_back(started_settings_log);
    drop(state);
    

    return HttpResponse::Ok().json(json!({ 
        "message": "Recorder started successfully",
        "recording": true,
        "started_at": Some(now)
    }))
}

#[post("/api/recorder/stop")]
async fn stop_recorder(recorder_state: ArtixSharedRecorder) -> impl Responder {
    {
        let check_state = recorder_state.lock().await;
        let is_recorder_running: bool = check_state.running;
        drop(check_state);

        if !is_recorder_running{ // Exit if not running
            return HttpResponse::BadRequest().json(json!({ 
                "message": "No recorder is running",
                "recording": false,
                "started_at": Option::<u64>::None
            }));
        }
    }

    let mut state = recorder_state.lock().await;
    state.running = false;
    state.started_at = None;
    let child = state.process.take();
    drop(state);

    if let Some(mut child) = child {
        let _ = child.kill().await;
        let _ = child.wait().await;
    }

    let mut state = recorder_state.lock().await;
    state.process = None;
    state.logs.push_back(Log {
        timestamp: chrono::Utc::now().timestamp() as u64,
        data: "<Stoped Manualy>".to_string()
    });
    drop(state);

    return HttpResponse::Ok().json(json!({ 
        "message": "Recorder stoped successfully",
        "recording": false,
        "started_at": Option::<u64>::None
    }))
}