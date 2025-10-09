use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use once_cell::sync::Lazy;
use serde::Serialize;
use serde_json::json;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;

static RECORDING_PROCESS: Lazy<Mutex<Option<Child>>> = Lazy::new(|| Mutex::new(None));
static RECORDING_NR: Lazy<Mutex<u32>> = Lazy::new(|| Mutex::new(0));

#[derive(Serialize)]
struct Message {
    message: String,
}

fn is_recording_alive(child: &mut Child) -> bool {
    match child.try_wait() {
        Ok(Some(_)) => false, // child exited
        Ok(None) => true,     // still running
        Err(_) => false,      // treat errors as dead
    }
}

// GET /api/status
async fn status() -> impl Responder {
    HttpResponse::Ok().json(Message {
        message: "API is online".to_string(),
    })
}

// GET /api/recorder/status
async fn recorder_status() -> impl Responder {
    let mut process_lock = RECORDING_PROCESS.lock().unwrap();

    let is_running: bool = if let Some(child) = process_lock.as_mut() {
        is_recording_alive(child)
    } else {
        false
    };

    let recording: bool = is_running;

    HttpResponse::Ok().json(json!({
        "recording": recording
    }))
}

// POST /api/recorder/start
async fn start_recording() -> impl Responder {
    let mut process_lock = RECORDING_PROCESS.lock().unwrap();
    let mut nr_lock = RECORDING_NR.lock().unwrap();

    // Check if there is a running process
    if let Some(child) = process_lock.as_mut() {
        if is_recording_alive(child) {
            return HttpResponse::BadRequest().json(Message {
                message: "Recording is already running.".to_string(),
            });
        } else {
            println!("Previous recording process has exited unexpectedly.");
            *process_lock = None; // clear dead process
        }
    }

    let station = format!("{:04}", *nr_lock);
    let cmd = Command::new("python3")
        .arg("kiwirecorder.py")
        .args([
            "-s", "127.0.0.1",
            "-p", "8073",
            "-m", "iq",
            "--kiwi-wav",
            "-d", "/var/recorder/recorded-files/",
            "--filename", "KiwiRecording",
            "--station", &station,
        ])
        .current_dir("/usr/local/src/kiwiclient/")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();

    match cmd {
        Ok(child) => {
            println!("Recording started, PID={}", child.id());
            *process_lock = Some(child);
            *nr_lock = (*nr_lock + 1) % 10_000;

            HttpResponse::Ok().json(Message {
                message: "Recording has started and will continue until stopped manually.".into(),
            })
        }
        Err(e) => HttpResponse::InternalServerError().json(Message {
            message: format!("Error starting recording: {}", e),
        }),
    }
}

// POST /api/recorder/stop
async fn stop_recording() -> impl Responder {
    let mut process_lock = RECORDING_PROCESS.lock().unwrap();

    if let Some(mut child) = process_lock.take() {
        if is_recording_alive(&mut child) {
            match child.kill() {
                Ok(_) => HttpResponse::Ok().json(Message {
                    message: "Recording stopped successfully.".to_string(),
                }),
                Err(e) => HttpResponse::InternalServerError().json(Message {
                    message: format!("Error stopping recording: {}", e),
                }),
            }
        } else {
            HttpResponse::Ok().json(Message {
                message: "Recording process was already stopped.".to_string(),
            })
        }
    } else {
        HttpResponse::BadRequest().json(Message {
            message: "No recording is running.".to_string(),
        })
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port: u16 = 5002;

    println!("Starting server on 0.0.0.0:{}", port);
    HttpServer::new(|| {
        App::new()
            .route("/api/status", web::get().to(status))
            .route("/api/recorder/status", web::get().to(recorder_status))
            .route("/api/recorder/start", web::post().to(start_recording))
            .route("/api/recorder/stop", web::post().to(stop_recording))
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}
