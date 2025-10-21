use actix_web::{get, post, web, App, HttpResponse, HttpServer, Responder};
use serde::Deserialize;
use serde_json::json;
use tokio::io::{AsyncBufReadExt, BufReader};
use std::collections::VecDeque;
use std::process::Stdio;
use std::sync::Arc;
use tokio::process::Child;
use tokio::sync::Mutex;

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum RecordingType {
    PNG,
    IQ
}

#[derive(Deserialize)]
struct RecorderSettings {
    rec_type: RecordingType,
    frequency: u32, // Hz
    #[serde(default)] // defaults zoom to 0 if not provided
    zoom: u8,
    autostop: u16 // Sec, O if infinite
}

struct RecorderState {
    running: bool,
    process: Option<Child>,
    started_at: Option<u64>,
    logs: VecDeque<String>,
}

type SharedRecorder = Arc<Mutex<RecorderState>>;
type ArtixSharedRecorder = actix_web::web::Data<SharedRecorder>;
type ArtixRecorderSettings = web::Json<RecorderSettings>;

async fn read_output(pipe: impl tokio::io::AsyncRead + Unpin, recorder: SharedRecorder, pipe_tag: &str, responsible_for_exit: bool) {
    let reader = BufReader::new(pipe);
    let mut lines = reader.lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let mut state = recorder.lock().await;
        state.logs.push_back(format!("[{}] {}: {}", chrono::Utc::now().format("%Y/%m/%d %H:%M:%S UTC").to_string(), pipe_tag, line));
        if state.logs.len() > 997 {
            state.logs.pop_front();
        }

    }
    if responsible_for_exit {
        let mut state = recorder.lock().await;
        state.running = false;
        state.started_at = None;
        state.logs.push_back(format!("[{}]: <Exited>", chrono::Utc::now().format("%Y/%m/%d %H:%M:%S UTC").to_string()));
    }
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
    const MAX_LOG_LENGTH: usize = 100;

    let state = recorder_state.lock().await;
    let is_recording = state.running;
    let started_at = state.started_at;
    let logs = state.logs.clone();
    drop(state);

    let last_5_logs: Vec<String> = logs
        .iter()
        .rev() // start from the newest
        .take(5)
        .map(|log| {
            if log.len() > MAX_LOG_LENGTH {
                format!("{}...", &log[..MAX_LOG_LENGTH])
            } else {
                log.clone()
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
        "last_logs": last_5_logs
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
    
    let filename_common = format!("{}_Freq-{}Hz", chrono::Utc::now().format("%Y-%m-%d_%H-%M-%S_UTC").to_string(), settings.frequency.to_string());
    let filename_png = format!("{}_Zoom-{}", filename_common, settings.zoom.to_string());
    let filename_iq = format!("{}_Bandwidth-12kHz", filename_common);

    let mut args: Vec<String>  = match settings.rec_type {
        RecordingType::PNG => vec![
            "-s".to_string(), "127.0.0.1".to_string(),
            "-p".to_string(), "8073".to_string(),
            format!("--freq={:#.3}", (settings.frequency as f64 / 1000.0)),
            "-d".to_string(), "/var/recorder/recorded-files/".to_string(),
            "--filename=KiwiRecording".to_string(),
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
            "--filename=KiwiRecording".to_string(),
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
    
    let now = chrono::Utc::now();
    let started_at = Some(now.timestamp() as u64);
    let started_at_str = now.format("%Y/%m/%d %H:%M:%S UTC").to_string();
    let mut state = recorder_state.lock().await;
    state.process = Some(child);
    state.running = true;
    state.started_at = started_at;
    state.logs.push_back(format!("[{}]: <Started>", started_at_str));
    drop(state);
    

    return HttpResponse::Ok().json(json!({ 
        "message": "Recorder started successfully",
        "recording": true,
        "started_at": started_at
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
    state.logs.push_back(format!("[{}]: <Stoped Manualy>", chrono::Utc::now().format("%Y/%m/%d %H:%M:%S UTC").to_string()));
    drop(state);

    return HttpResponse::Ok().json(json!({ 
        "message": "Recorder stoped successfully",
        "recording": false,
        "started_at": Option::<u64>::None
    }))
}