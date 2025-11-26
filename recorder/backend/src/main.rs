use actix_web::{App, HttpResponse, HttpServer, Responder, delete, get, post, web::{self, Data, Path}};
use serde::{Serialize, Deserialize};
use serde_json::json;
use std::{collections::{HashMap, VecDeque}, fmt::{self, Display, Formatter}, io::Result, process::Stdio, sync::Arc};
use tokio::{process::Child, sync::Mutex, io::{AsyncBufReadExt, BufReader, AsyncRead}};
use chrono::Utc;

#[derive(Clone, Serialize, Deserialize)]
struct Log {
    timestamp: u64, // Unix
    data: String
}

type Logs = VecDeque<Log>;

#[derive(Deserialize, Serialize, Clone, Copy)]
#[serde(rename_all = "lowercase")]
enum RecordingType {
    PNG,
    IQ
}

impl Display for RecordingType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            RecordingType::PNG => write!(f, "Png"),
            RecordingType::IQ => write!(f, "Iq"),
        }
    }
}

#[derive(Deserialize, Serialize, Clone, Copy)]
struct RecorderSettings {
    rec_type: RecordingType,
    frequency: u32, // Hz
    #[serde(default)] // defaults zoom to 0 if not provided
    zoom: u8,
    autostop: u16 // Sec, O if off
}

impl Display for RecorderSettings {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Type: {}, Frequency: {} Hz, {}Autostop: {}",
            self.rec_type,
            self.frequency,
            match self.rec_type {
                RecordingType::PNG => format!("Zoom: {} ", self.zoom),
                RecordingType::IQ => "".to_string()
            },
            if self.autostop == 0 { String::from("Off") } else { format!("{} sec", self.autostop.to_string()) }
        )
    }
}

type ArtixRecorderSettings = web::Json<RecorderSettings>;

#[derive(Serialize, Clone)]
struct JobStatus {
    job_id: u32,
    running: bool,
    started_at: Option<u64>,
    logs: Logs,
    settings: RecorderSettings,
}

impl From<&Job> for JobStatus {
    fn from(value: &Job) -> Self {
        const MAX_LOG_LENGTH: usize = 200;
        const LOG_COUNT: usize = 20;
        JobStatus {
            job_id: value.job_id,
            running: value.running,
            started_at: value.started_at,
            logs: value.logs.iter()
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
                .collect(),
            settings: value.settings, 
        }
    }
}

struct Job {
    job_id: u32,
    running: bool,
    process: Option<Child>,
    started_at: Option<u64>,
    logs: Logs,
    settings: RecorderSettings,
}

type SharedJob = Arc<Mutex<Job>>;
type SharedJobHashmap =  Arc<Mutex<HashMap<u32, SharedJob>>>;
type ArtixRecorderHashmap = web::Data<SharedJobHashmap>;    

async fn read_output(pipe: impl AsyncRead + Unpin, job: SharedJob, pipe_tag: &str, responsible_for_exit: bool) {
    let reader = BufReader::new(pipe);
    let mut lines = reader.lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let mut state = job.lock().await;
        state.logs.push_back(Log {
            timestamp: Utc::now().timestamp() as u64, 
            data: format!("<{}> {}", pipe_tag, line)
        });
        if state.logs.len() > 997 {
            state.logs.pop_front();
        }

    }
    if responsible_for_exit {
        let mut state = job.lock().await;
        state.running = false;
        state.started_at = None;
        state.logs.push_back(Log {
            timestamp: Utc::now().timestamp() as u64, 
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
async fn main() -> Result<()> {
    let port: u16 = 5004;

    let shared_hashmap: SharedJobHashmap = 
        Arc::new(
                Mutex::new(
                    HashMap::<u32, SharedJob>::new()
    ));

    println!("Starting server on port {}", port);
    HttpServer::new(move || {
        App::new()
            .app_data(Data::new(shared_hashmap.clone()))
            .service(status)
            .service(start_recorder)
            .service(stop_recorder)
            .service(recorder_status_all)
            .service(recorder_status_one)
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}

#[get("/api/")]
async fn status() -> impl Responder {
    HttpResponse::Ok().body(
        "Api is Online"
    )
}

#[get["/api/recorder/status"]]
async fn recorder_status_all(shared_hashmap: ArtixRecorderHashmap) -> impl Responder {
    let mut locked_jobs: Vec<SharedJob> = Vec::new();

    let hashmap = shared_hashmap.lock().await;
    for key in hashmap.keys() {
        locked_jobs.push(hashmap[key].clone());
    }
    drop(hashmap);

    let mut jobs: Vec<JobStatus> = Vec::new();
    for locked_job in locked_jobs {
        let job_guard = locked_job.lock().await;
        let job_status = JobStatus::from(&*job_guard);
        drop(job_guard);
        jobs.push(job_status);
    }
    HttpResponse::Ok().json(jobs)
}

#[get("/api/recorder/status/{job_id}")]
async fn recorder_status_one(path: Path<u32>, shared_hashmap: ArtixRecorderHashmap) -> impl Responder {
    let job_id = path.into_inner();

    let hashmap = shared_hashmap.lock().await;
    let shared_job = (hashmap.get(&job_id)).cloned();
    drop(hashmap);

    if shared_job.is_none() {
        return HttpResponse::BadRequest().json(json!({
            "message": "Job not found: job_id not valid"
        }));
    }

    let job_status = JobStatus::from(&*(shared_job.unwrap().lock().await));
    return HttpResponse::Ok().json(job_status)
}

#[post("/api/recorder/start")]
async fn start_recorder(request_settings_raw: ArtixRecorderSettings, shared_hashmap: ArtixRecorderHashmap) -> impl Responder {
    const MAX_RECORDER_SLOTS: usize = 3;
    let settings = request_settings_raw.into_inner();
    { // Check if all recorder slots are full (Only start a new recorder if there is at least 1 empty slot)
        let hashmap = shared_hashmap.lock().await;
        let used_recorder_slots = hashmap.keys().len();
        drop(hashmap);

        if used_recorder_slots >= MAX_RECORDER_SLOTS {
            return HttpResponse::BadRequest().json(json!({ 
                "message": "All recorder slots are full",
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
        let selection_freq_min = (center_freq as i64).saturating_sub((bandwidth as i64) / 2);

        if selection_freq_max > MAX_FREQ {
            return HttpResponse::BadRequest().json(json!({ 
                "message": "The selected frequency range exceeds the maximum frequency",
                "recording": false,
                "started_at": Option::<u64>::None
            }));
        }
        if selection_freq_min < MIN_FREQ as i64 {
            return HttpResponse::BadRequest().json(json!({ 
                "message": "The selected frequency range exceeds the minimum frequency",
                "recording": false,
                "started_at": Option::<u64>::None
            }));
        }
    }
    
    // Generate job_id
    let hashmap = shared_hashmap.lock().await;
    let job_id: u32 = (u32::MIN..u32::MAX)
        .find(|&id| !hashmap.contains_key(&id))
        .expect("Job ID space exhausted");
    drop(hashmap);

    

    let filename_common = format!("{}_Fq{}", Utc::now().format("%Y-%m-%d_%H-%M-%S_UTC").to_string(), to_scientific(settings.frequency));
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

    let now = Utc::now().timestamp() as u64;
    let started_at_log = Log {
        timestamp: now,
        data: "<Started>".to_string()
    };
    let started_settings_log = Log {
        timestamp: now,
        data: format!("<Settings>  {}", settings)
    };

    let job = Job {
        job_id: job_id,
        running: true,
        process: None,
        started_at: Some(now),
        logs: VecDeque::from(vec![started_at_log, started_settings_log]),
        settings: settings,
    };

    let shared_job: SharedJob = Arc::new(Mutex::new(job));

    if let Some(stdout) = child.stdout.take() {
        tokio::spawn(read_output(stdout, shared_job.clone(), "STDOUT", true));
    }
    if let Some(stderr) = child.stderr.take() {
       tokio::spawn(read_output(stderr, shared_job.clone(), "STDERR", false));
    }

    let mut job2 = shared_job.lock().await;
    job2.process = Some(child);
    drop(job2);

    let mut hashmap = shared_hashmap.lock().await;
    hashmap.insert(job_id, shared_job.clone());
    drop(hashmap);

    let job_status = JobStatus::from(&*(shared_job.lock().await));
    HttpResponse::Ok().json(job_status)
}

#[post("/api/recorder/stop/{job_id}")]
async fn stop_recorder(path: Path<u32>, shared_hashmap: ArtixRecorderHashmap) -> impl Responder {
    let job_id = path.into_inner();

    let hashmap = shared_hashmap.lock().await;
    let option_shared_job = (hashmap.get(&job_id)).cloned();
    drop(hashmap);

    if option_shared_job.is_none() {
        return HttpResponse::BadRequest().json(json!({
            "message": "Job not found: job_id not valid"
        }));
    }

    let shared_job: SharedJob = option_shared_job.unwrap();

    let mut job = shared_job.lock().await;
    let child = job.process.take();
    drop(job);

    if let Some(mut child) = child {
        let _ = child.kill().await;
        let _ = child.wait().await;
    }

    let mut job = shared_job.lock().await;
    job.process = None;
    job.logs.push_back(Log {
        timestamp: Utc::now().timestamp() as u64,
        data: "<Stoped Manualy>".to_string()
    });

    let job_status = JobStatus::from(&*job);
    HttpResponse::Ok().json(job_status)
}

#[delete("/api/recorder/stop/{job_id}")]
async fn remove_recorder(path: Path<u32>, shared_hashmap: ArtixRecorderHashmap) -> impl Responder {
    let job_id = path.into_inner();

    let mut hashmap = shared_hashmap.lock().await;
    let option_shared_job = hashmap.remove(&job_id);
    drop(hashmap);

    if option_shared_job.is_none() {
        return HttpResponse::BadRequest().json(json!({
            "message": "Job not found: job_id not valid"
        }));
    }

    let shared_job: SharedJob = option_shared_job.unwrap();
    let mut job = shared_job.lock().await;
    let child = job.process.take();
    drop(job);

    if let Some(mut child) = child {
        let _ = child.kill().await;
        let _ = child.wait().await;
    }
    
    HttpResponse::Ok().json(json!({
        "message": "Recorder deleted successfully",
    }))
}