use actix_web::{get, post, App, HttpResponse, HttpServer, Responder};
use serde_json::json;
use chrono;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port: u16 = 5004;
    
    println!("Starting server on port {}", port);
    HttpServer::new(|| {
        App::new()
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
async fn start_recorder() -> impl Responder {

    let start_time = chrono::Utc::now().to_rfc3339();
    HttpResponse::Ok().json(json!({ 
        "recording": true, 
        "started_at": start_time
    }))
}
