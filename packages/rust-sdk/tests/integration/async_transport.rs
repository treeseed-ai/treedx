use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use serde_json::json;
use treedx::TreeDxConfig;
use treedx::auth::StaticBearerTokenAuthProvider;
use treedx::transport::{ReqwestTransport, Transport, TreeDxHttpMethod, TreeDxRequest};

async fn request(
    status: &'static str,
    body: &'static str,
) -> treedx::error::TreeDxResult<treedx::transport::TreeDxResponse> {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let address = listener.local_addr().unwrap();
    let server = thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut socket = loop {
            match listener.accept() {
                Ok((socket, _)) => break socket,
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    assert!(
                        Instant::now() < deadline,
                        "HTTP fixture did not receive a request"
                    );
                    thread::sleep(Duration::from_millis(10));
                }
                Err(error) => panic!("HTTP fixture accept failed: {error}"),
            }
        };
        socket
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        socket
            .set_write_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut bytes = Vec::new();
        while !bytes.windows(4).any(|part| part == b"\r\n\r\n") {
            let mut chunk = [0; 1024];
            let count = socket.read(&mut chunk).unwrap();
            assert!(count > 0);
            bytes.extend_from_slice(&chunk[..count]);
            assert!(bytes.len() <= 16_384);
        }
        let request = String::from_utf8(bytes).unwrap();
        assert!(
            request.starts_with("GET /api/v1/health HTTP/1.1\r\n"),
            "unexpected request line: {:?}",
            request.lines().next()
        );
        assert!(
            request
                .to_lowercase()
                .contains("authorization: bearer fixture\r\n")
        );
        write!(socket, "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
    });
    let transport: Arc<dyn Transport> = Arc::new(ReqwestTransport::new(TreeDxConfig {
        base_url: format!("http://{address}"),
        auth_provider: Some(Arc::new(StaticBearerTokenAuthProvider::new("fixture"))),
        timeout: Some(Duration::from_secs(5)),
        ..Default::default()
    }));
    let owned = transport.clone();
    let result = tokio::spawn(async move {
        owned
            .request(TreeDxRequest::new(TreeDxHttpMethod::Get, "/api/v1/health"))
            .await
    })
    .await
    .unwrap();
    server.join().unwrap();
    result
}

#[tokio::test]
async fn boxed_send_transport_preserves_real_http_success() {
    let response = request("200 OK", "{\"data\":{\"ok\":true}}").await.unwrap();
    assert_eq!(response.status, 200);
    assert_eq!(response.data, json!({"data":{"ok":true}}));
}

#[tokio::test]
async fn boxed_send_transport_preserves_real_http_denial() {
    let error = request(
        "401 Unauthorized",
        "{\"error\":{\"code\":\"unauthorized\",\"message\":\"denied\"}}",
    )
    .await
    .unwrap_err();
    assert_eq!(error.status, 401);
    assert_eq!(error.code, "unauthorized");
    assert_eq!(error.message, "denied");
    assert_eq!(
        error.payload,
        Some(json!({"error":{"code":"unauthorized","message":"denied"}}))
    );
}

#[tokio::test]
async fn boxed_send_transport_preserves_real_http_malformed_json_failure() {
    let error = request("200 OK", "not-json").await.unwrap_err();
    assert_eq!(error.status, 0);
    assert_eq!(error.code, "network_error");
}
