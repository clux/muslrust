# muslrust
[![build status](https://secure.travis-ci.org/clux/muslrust.svg)](http://travis-ci.org/clux/muslrust)
[![docker pulls](https://img.shields.io/docker/pulls/clux/muslrust.svg)](
https://hub.docker.com/r/clux/muslrust/)

A plain docker environment for building static binaries compiled with rust and linked against musl instead of glibc. Built nightly on travis.

This is useful if you require external C dependencies, and/or need a CI image to compile a musl binary. Locally, you could do `rustup target add x86_64-unknown-linux-musl` if you don't need C dependencies.

This container [comes with a bunch of statically compiled C libraries](#c-libraries) using `musl-gcc` so that we can statically link against these as well.

For embedded targets, consider [cross](https://github.com/japaric/cross) as a more general solution.

## Usage
Pull and run from a rust project root:

```sh
docker pull clux/muslrust
docker run -v $PWD:/volume --rm -t clux/muslrust cargo build
```

You should have a static executable in the target folder:

```sh
ldd target/x86_64-unknown-linux-musl/debug/EXECUTABLE
        not a dynamic executable
```

From there on, you can include it in a blank docker image, distroless/static, or alpine (if you absolutely need kubectl exec), and you can end up with say:

- [4MB blog image (blank image)](https://github.com/clux/blog).
- [6MB kubernetes controller with actix (distroless/static)](https://github.com/kube-rs/controller-rs)

or you can use it to [embed your no-dependency binary straight into github releases](https://github.com/gleam-lang/gleam/blob/8333cd3a402b920dc774a4d8761ca28ceff09738/.github/workflows/release.yaml) and not have to worry about what libc your users are on.

## Docker builds
Latest is always the last built nightly pushed by travis. To pin against specific builds, see the [available tags](https://hub.docker.com/r/clux/muslrust/tags/) on the docker hub.

## C Libraries
The following system libraries are compiled against `musl-gcc`:

- [x] curl ([curl crate](https://github.com/carllerche/curl-rust))
- [x] openssl ([openssl crate](https://github.com/sfackler/rust-openssl))
- [x] pq ([pq-sys crate](https://github.com/sgrif/pq-sys) used by [diesel](https://github.com/diesel-rs/diesel))
- [x] sqlite3 ([libsqlite3-sys crate](https://github.com/jgallagher/rusqlite/tree/master/libsqlite3-sys) used by [diesel](https://github.com/diesel-rs/diesel))
- [x] zlib (used by pq and openssl)

We try to keep these up to date.

If it weren't for pq, we could ditch zlib as the `flate2` crate bundles `miniz.c` as the default implementation, and this just works. Similarly, curl is only needed for people using the C bindings to curl over [hyper](https://hyper.rs/).

If you need extra dependencies, you can follow the builder pattern approach by [portier-broker](https://github.com/portier/portier-broker/blob/master/Dockerfile)

## Developing
Clone, tweak, build, and run tests:

```sh
git clone git@github.com:clux/muslrust.git && cd muslrust
make build
make test
```

Before we push a new version of muslrust we ensure that we can use and statically link:

- [x] `serde`
- [x] `diesel` (postgres and sqlite - see note below for postgres)
- [x] `hyper`
- [x] `curl`
- [x] `openssl`
- [x] `flate2`
- [x] `rand`
- [ ] `rocket` (waiting for stable release)

## SSL Verification
You need to point openssl at the location of your certificates explicitly to have https requests not return certificate errors.

```sh
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export SSL_CERT_DIR=/etc/ssl/certs
```

You can also hardcode this in your binary, or, more sensibly set it in your running docker image. The [openssl-probe crate](https://crates.io/crates/openssl-probe) can be also be used to detect where these reside.

## Diesel and PQ builds
Works with the older version of libpq we bundle (see [#81](https://github.com/clux/muslrust/issues/81)). See the [test/dieselpgcrate](./test/dieselpgcrate) for specifics.

For stuff like `infer_schema!` to work you need to explicitly pass on `-e DATABASE_URL=$DATABASE_URL` to the `docker run`. It's probably easier to just make `diesel print-schema > src/schema.rs` part of your migration setup though.

Note that diesel compiles with `openssl` statically since `1.34.0`, so you need to include the `openssl` crate **before** `diesel` due to [pq-sys#25](https://github.com/sgrif/pq-sys/issues/25):

```rs
extern crate openssl;
#[macro_use] extern crate diesel;
```

This is true even if you connect without `sslmode=require`.

## Caching Cargo Locally
Repeat builds locally are always from scratch (thus slow) without a cached cargo directory. You can set up a docker volume by just adding `-v cargo-cache:/root/.cargo/registry` to the docker run command.

You'll have an extra volume that you can inspect with `docker volume inspect cargo-cache`.

Suggested developer usage is to add the following function to your `~/.bashrc`:

```sh
musl-build() {
  docker run \
    -v cargo-cache:/root/.cargo/registry \
    -v "$PWD:/volume" \
    --rm -it clux/muslrust cargo build --release
}
```

Then use in your project:

```sh
$ cd myproject
$ musl-build
    Finished release [optimized] target(s) in 0.0 secs
```

Second time around this will be quick, and you can even mix it with native `cargo build` calls without screwing with your cache.

## Debugging in blank containers
If you are running a plain alpine/scratch container with your musl binary in there, then you might need to compile with debug symbols, and set `ENV RUST_BACKTRACE=full` in your `Dockerfile`.

In alpine, if even this doesn't work (or fails to give you line numbers), try installing the `rust` package (via `apk`). This should not be necessary anymore though!

For easily grabbing backtraces from rust docker apps; try adding [sentry](https://crates.io/crates/sentry). It seems to be able to grab backtraces regardless of compile options/evars.

## Using muslrust on CI
Due to the current best compatibility with docker caching strategies, recommended CI is Circle. See [webapp-rs](https://github.com/clux/webapp-rs), [operator-rs](https://github.com/clux/operator-rs), or [raftcat](https://github.com/Babylonpartners/shipcat/tree/master/raftcat) for complete life-cycle rust cloud applications running in alpine containers built on CI (first two are demos, second one has more stuff).

### Extra Rustup components
You can install extra components distributed via Rustup like normal:

```sh
rustup component add clippy
```

### Binaries distributed via Cargo
If you need to install a binary crate such as [ripgrep](https://github.com/BurntSushi/ripgrep) on a CI build image, you need to build it against the GNU toolchain (see [#37](https://github.com/clux/muslrust/issues/37#issuecomment-357314202)):

```sh
CARGO_BUILD_TARGET=x86_64-unknown-linux-gnu cargo install ripgrep
```

## SELinux
On SELinux enabled systems like Fedora, you will need to [configure selinux labes](https://docs.docker.com/storage/bind-mounts/#mounting-into-a-non-empty-directory-on-the-container). E.g. adding the `:Z` or `:z` flags where appropriate: `-v $PWD:/volume:Z`.
