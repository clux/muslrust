use hyper_tls::HttpsConnector;
use hyper::{body::HttpBody as _, Client};
use tokio::io::{self, AsyncWriteExt as _};

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>>{
    // set SSL_CERT location - see issue #5
    // normally you'd want to set this in your container
    // but for plain bin distribution and this test, we set it here
    std::env::set_var("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt");

    let url = "https://raw.githubusercontent.com/clux/muslrust/master/README.md";

    let https = HttpsConnector::new();
    let client = Client::builder().build::<_, hyper::Body>(https);

    let mut res = client.get(url.parse()?).await?;
    assert_eq!(res.status(), 200);

    while let Some(next) = res.data().await {
        let chunk = next?;
        io::stdout().write_all(&chunk).await?;
    }

    Ok(())
}
