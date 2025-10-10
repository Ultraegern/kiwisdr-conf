use actix_web::{get, post, web, App, HttpResponse, HttpServer, Responder};
use serde_json::json;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port: u16 = 5004;
    println!("Starting server on port {}", port);

    HttpServer::new(|| {
        App::new()
            .service(status)
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}

#[get("/api/status")]
async fn status() -> impl Responder {
    HttpResponse::Ok().json(json!({ 
        "status": "Api is Online" 
    }))
}

