use actix_web::{get, post, App, HttpResponse, HttpServer, Responder};
use serde_json::json;
use tokio::io::{AsyncBufReadExt, BufReader};
use std::collections::VecDeque;
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tokio::process::Child;
use tokio::sync::Mutex;

struct RecorderState {
    running: bool,
    process: Option<Child>,
    started_at: Option<Instant>,
    logs: VecDeque<String>,
}

type SharedRecorder = Arc<Mutex<RecorderState>>;

fn get_start_time_unix(started_at: Option<Instant>) -> Option<u64> {
    let now_unix: u64 = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_secs();
    let seconds_since_start: u64 = Instant::now().duration_since(started_at?).as_secs();
    let start_unix: u64 = now_unix.saturating_sub(seconds_since_start);
    return Some(start_unix);
}

async fn read_output(pipe: impl tokio::io::AsyncRead + Unpin, recorder: SharedRecorder, pipe_tag: &str, responsible_for_exit: bool) {
    let reader = BufReader::new(pipe);
    let mut lines = reader.lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let mut state = recorder.lock().await;
        state.logs.push_back(format!("[{}] {}: {}", chrono::Utc::now().to_rfc3339(), pipe_tag, line));
        if state.logs.len() > 997 {
            state.logs.pop_front();
        }

    }
    let mut state = recorder.lock().await;
    state.logs.push_back(format!("[{}] {}: <closed>", chrono::Utc::now().to_rfc3339(), pipe_tag));
    if responsible_for_exit {
        state.running = false;
        state.started_at = None;
        state.logs.push_back(format!("[{}]: <exited>", chrono::Utc::now().to_rfc3339()));
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

#[post("/api/recorder/start")]
async fn start_recorder(recorder_state: actix_web::web::Data<SharedRecorder>) -> impl Responder {
    {
        let check_state = recorder_state.lock().await;
        let is_recorder_running: bool = check_state.running;
        let recorder_start_time: Option<Instant> = check_state.started_at;
        drop(check_state);

        if is_recorder_running{ // Exit if already running
            return HttpResponse::BadRequest().json(json!({ 
                "message": "Recorder is already running",
                "recording": true,
                "started_at": get_start_time_unix(recorder_start_time)
            }));
        }
    }

    let mut child: Child = tokio::process::Command::new("ping")
        .arg("1.1.1.1")
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
    
    let mut state = recorder_state.lock().await;
    state.process = Some(child);
    state.running = true;
    state.started_at = Some(Instant::now());
    let started_at: Option<Instant> = state.started_at;
    drop(state);
    

    return HttpResponse::Ok().json(json!({ 
        "message": "Recorder started successfully",
        "recording": true,
        "started_at": get_start_time_unix(started_at)
    }))
}

#[post("/api/recorder/stop")]
async fn stop_recorder(recorder_state: actix_web::web::Data<SharedRecorder>) -> impl Responder {
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

    return HttpResponse::Ok().json(json!({ 
        "message": "Recorder stoped successfully",
        "recording": false,
        "started_at": Option::<u64>::None
    }))
}