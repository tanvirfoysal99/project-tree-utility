//! Loopback-only transport tests. No credentials, public APIs, or external network.
use project_tree_utility::remote;
use reqwest::{Url, blocking::Client};
use std::{
    io::{Read, Write},
    net::TcpListener,
    thread,
    time::{Duration, Instant},
};

fn server(responses: Vec<String>) -> (Url, thread::JoinHandle<Vec<String>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let url = Url::parse(&format!(
        "http://{}/fixture",
        listener.local_addr().unwrap()
    ))
    .unwrap();
    let handle = thread::spawn(move || {
        let mut requests = vec![];
        let deadline = Instant::now() + Duration::from_secs(8);
        for response in responses {
            let mut stream = loop {
                match listener.accept() {
                    Ok((stream, _)) => break stream,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        assert!(Instant::now() < deadline, "fixture timed out");
                        thread::sleep(Duration::from_millis(10));
                    }
                    Err(error) => panic!("{error}"),
                }
            };
            stream.set_nonblocking(false).unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(2)))
                .unwrap();
            let mut request = vec![];
            let mut byte = [0u8];
            while !request.ends_with(b"\r\n\r\n") {
                stream.read_exact(&mut byte).unwrap();
                request.push(byte[0]);
                assert!(request.len() < 16_384);
            }
            requests.push(String::from_utf8(request).unwrap());
            let _ = stream.write_all(response.as_bytes());
        }
        requests
    });
    (url, handle)
}

fn response(status: &str, body: &str, extra: &str) -> String {
    format!(
        "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n{extra}\r\n{body}",
        body.len()
    )
}
fn client() -> Client {
    Client::builder()
        .timeout(Duration::from_secs(2))
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap()
}

#[test]
fn retries_transient_errors_and_preserves_authorization_header() {
    let (url, handle) = server(vec![
        response("503 Service Unavailable", "", ""),
        response("200 OK", "{\"ok\":true}", "X-Next-Page: 2\r\n"),
    ]);
    let (value, headers) = remote::request(&client(), url, Some("dummy-fixture-token")).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(headers["x-next-page"], "2");
    let requests = handle.join().unwrap();
    assert_eq!(requests.len(), 2);
    assert!(requests.iter().all(|s| {
        s.to_lowercase()
            .contains("authorization: bearer dummy-fixture-token")
    }));
}

#[test]
fn redirects_are_rejected_without_following_them() {
    let (url, handle) = server(vec![response(
        "302 Found",
        "",
        "Location: https://example.invalid/do-not-contact\r\n",
    )]);
    assert!(remote::request(&client(), url, None).is_err());
    assert_eq!(handle.join().unwrap().len(), 1);
}

#[test]
fn malformed_json_and_oversized_response_headers_fail() {
    for reply in [
        response("200 OK", "not json", ""),
        "HTTP/1.1 200 OK\r\nContent-Length: 33554433\r\nConnection: close\r\n\r\n".into(),
    ] {
        let (url, handle) = server(vec![reply]);
        assert!(remote::request(&client(), url, None).is_err());
        handle.join().unwrap();
    }
}

#[test]
fn retries_have_a_fixed_attempt_bound() {
    let (url, handle) = server(vec![response("429 Too Many Requests", "", ""); 3]);
    assert!(remote::request(&client(), url, None).is_err());
    assert_eq!(handle.join().unwrap().len(), 3);
}
