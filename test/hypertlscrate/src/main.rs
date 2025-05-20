//- Example from https://docs.rs/hyper-rustls/latest/hyper_rustls/
use http_body_util::Empty;
use hyper::body::Bytes;
use hyper::http::StatusCode;
use hyper_util::client::legacy::Client;
use hyper_util::rt::TokioExecutor;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let url = ("https://raw.githubusercontent.com/clux/muslrust/master/README.md")
        .parse()
        .unwrap();

    let https = hyper_rustls::HttpsConnectorBuilder::new()
        .with_native_roots()
        .expect("no native root CA certificates found")
        .https_only()
        .enable_http1()
        .build();

    let client: Client<_, Empty<Bytes>> = Client::builder(TokioExecutor::new()).build(https);

    let res = client.get(url).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    Ok(())
}
