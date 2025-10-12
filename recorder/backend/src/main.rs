use actix_web::{get, post, App, HttpResponse, HttpServer, Responder};
use serde_json::json;
use chrono;
use std::collections::VecDeque;
use std::sync::Arc;
use tokio::process::Child;
use tokio::sync::Mutex;

struct RecorderState {
    running: bool,
    process: Option<Child>,
    started_at: Option<i64>, // UNIX timestamp
    logs: VecDeque<String>,
}

type SharedRecorder = Arc<Mutex<RecorderState>>;

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
    let mut state = recorder_state.lock().await;

    if state.running { // Exit if already running
        return HttpResponse::BadRequest().json(json!({ 
            "message": "Recorder is already running",
            "recording": true,
            "started_at": state.started_at
        }));
    }

    let mut child: Child = tokio::process::Command::new("ping")
        .args(&["-t", "8.8.8.8"])
        .spawn()
        .expect("Failed to start recorder process");
    state.process = Some(child);
    state.running = true;
    state.started_at = Some(chrono::Utc::now().timestamp());

    return HttpResponse::Ok().json(json!({ 
        "message": "Recorder started successfully",
        "recording": true,
        "started_at": state.started_at
    }))
}