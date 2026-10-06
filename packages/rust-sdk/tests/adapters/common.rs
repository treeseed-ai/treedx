include!("mock_transport.rs");

pub fn request_keys(mock: &MockTransport) -> Vec<String> {
    mock.requests
        .lock()
        .unwrap()
        .iter()
        .map(|request| format!("{} {}", request.method.as_str(), request.path))
        .collect()
}
