# muslrust

[![nightly](https://github.com/clux/muslrust/actions/workflows/nightly.yml/badge.svg)](https://github.com/clux/muslrust/actions/workflows/nightly.yml)
[![stable](https://github.com/clux/muslrust/actions/workflows/stable.yml/badge.svg)](https://github.com/clux/muslrust/actions/workflows/stable.yml)
[![docker pulls](https://img.shields.io/docker/pulls/clux/muslrust.svg)](https://hub.docker.com/r/clux/muslrust/tags)

A docker environment for building **static** rust binaries for `x86_64` and `arm64` environments using **[musl](https://musl.libc.org/)**. Built daily via [github actions](https://github.com/clux/muslrust/actions).

Binaries compiled with `muslrust` are **light-weight**, call straight into the kernel without other dynamic system library dependencies, can be shipped to most  distributions without compatibility issues, and can be inserted as-is into lightweight docker images such as [static distroless](https://github.com/GoogleContainerTools/distroless/blob/main/base/README.md), [scratch](https://hub.docker.com/_/scratch), or [alpine](https://hub.docker.com/_/alpine).

The goal is to **simplify** the creation of small and **efficient cloud containers**, or **stand-alone linux binary releases**.

This image includes some hard-to-avoid [C libraries](#c-libraries) compiled with `musl-gcc`, enabling static builds even when these libraries are used.

## Usage

Pull and run from a rust project root:

```sh
docker pull clux/muslrust:stable
docker run -v $PWD:/volume --rm -t clux/muslrust:stable cargo build --release
```

You should have a static executable in the target folder:

```sh
ldd target/x86_64-unknown-linux-musl/release/EXECUTABLE
        not a dynamic executable
```

## Examples

- [Kubernetes controller with actix-web using plain distroless/static](https://github.com/kube-rs/controller-rs/blob/main/Dockerfile)
- [Kubernetes reflector with axum using builder pattern](https://github.com/kube-rs/version-rs/blob/main/Dockerfile)
- [Kubernetes controller using cargo-chef for caching layers](https://github.com/qualified/ephemeron/blob/main/k8s/controller/Dockerfile)
- [Github release assets uploaded via github actions](https://github.com/kube-rs/kopium/blob/f554ad9780dec3c76b4cef8a16a02bc82dded2be/.github/workflows/release.yml)
- [Using muslrust with sccache & github actions](./SCCACHE.md)

The binaries and images for small apps generally end up `<10MB` compressed or `~20MB` uncompressed without stripping.

The **recommended** production image is [distroless static](https://github.com/GoogleContainerTools/distroless/tree/main/base) or [chainguard static](https://github.com/chainguard-images/images/tree/main/images/static) as these contain a non-root users + SSL certs (unlike `scratch`), and disallows shell access (use `kubectl debug` if you want this). See also [kube.rs security doc on base image recommendations](https://kube.rs/controllers/security/#base-images).

## Available Tags

The standard tags are **`:stable`** or a dated **`:nightly-{YYYY-mm-dd}`**.

For pinned, or historical builds, see the [available tags on dockerhub](https://hub.docker.com/r/clux/muslrust/tags/).

## C Libraries

The following system libraries are compiled against `musl-gcc`:

- sqlite3 ([libsqlite3-sys crate](https://github.com/jgallagher/rusqlite/tree/master/libsqlite3-sys) used by [diesel](https://github.com/diesel-rs/diesel))
- zlib

These dependencies are updated with renovate from git releases.

Note that these libraries **may be removed** if sensible and popular Rust crates can replace them in the future.

Removed Libraries;

- `openssl` has been removed in 2025. See [#153](https://github.com/clux/muslrust/issues/153).
- `curl` has been removed in 2025. See [#96](https://github.com/clux/muslrust/issues/96).
- `pq` has been removed in 2025. See [#81](https://github.com/clux/muslrust/issues/81)

Consider [blackdex/rust-musl](https://github.com/BlackDex/rust-musl) for `openssl`, `curl` and `pq`.

If you need the old `openssl`/`pq`, you __can__ temporarily add them back to your own image as per [this comment](https://github.com/clux/muslrust/issues/168#issuecomment-3027429098).

## Developing

Clone, tweak, build, and run tests:

```sh
git clone git@github.com:clux/muslrust.git && cd muslrust
just build
just test
```

## Tests

Before we push a new version of muslrust we [test](https://github.com/clux/muslrust/blob/main/test.sh#L4-L17) to ensure that we can use and statically link:

- [x] [serde](https://crates.io/crates/serde)
- [x] [diesel](https://crates.io/crates/diesel) (using sqlite)
- [x] [rustls](https://crates.io/crates/rustls)
- [x] [hyper](https://crates.io/crates/hyper) (using hyper-rustls and rustls's default crypto backend)
- [x] [flate2](https://crates.io/crates/flate2)
- [x] [rand](https://crates.io/crates/rand)

## Caching

### Local Volume Caches

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

## Caching on CI

On CI, you need to find a way to either store the `cargo-cache` referenced above, or rely on docker layer caches with layers (see [`cargo-chef`](https://github.com/LukeMathWalker/cargo-chef)).

#### Github Actions
Github actions supports both methods:

- [GHA: direct folder cache (manual docker build)](https://github.com/kube-rs/controller-rs/blob/607d824d3a34959c5eded9c54f6f5c1bd14dc78e/.github/workflows/ci.yml#L67-L85)
- [GHA: via docker layer caches (builder-pattern)](https://github.com/qualified/ephemeron/blob/fc52e2b0373c4ebfba552e8a0d402dee0bc08f9c/.github/workflows/images.yaml#L30-L48) (with `cargo-chef`)

#### CircleCI
CircleCI supports both methods:

- [Circle: direct folder cache (manual docker build)](https://github.com/clux/webapp-rs/blob/master/.circleci/config.yml)
- Circle also supports [docker layer caching](https://circleci.com/docs/2.0/docker-layer-caching/) (no example atm)

## Allocator Performance

To optimise memory performance (see [#142](https://github.com/clux/muslrust/issues/142)) consider changing the global allocators in sensitive applications:

- [jemalloc](https://github.com/tikv/jemallocator)
- [mimalloc](https://github.com/microsoft/mimalloc)

```rust
use tikv_jemallocator::Jemalloc;
#[global_allocator]
static GLOBAL: Jemalloc = Jemalloc;
```

## Troubleshooting

### Filesystem permissions on local builds

When building locally, the permissions of the musl parts of the `./target` artifacts dir will be owned by `root` and requires `sudo rm -rf target/` to clear. This is an [intended](https://github.com/clux/muslrust/issues/65) complexity tradeoff with user builds.

### Debugging in blank containers

If you are running a plain alpine/scratch container with your musl binary in there, then you might need to compile with debug symbols, and set the `RUST_BACKTRACE=full` evar to see crashes.

In alpine, if this doesn't work (or fails to give you line numbers), try installing the `rust` package (via `apk`). This should not be necessary anymore though!

For easily grabbing backtraces from rust docker apps; try adding [sentry](https://crates.io/crates/sentry). It seems to be able to grab backtraces regardless of compile options/evars.

### SELinux

On SELinux enabled systems like Fedora, you will need to [configure selinux labels](https://docs.docker.com/storage/bind-mounts/#mounting-into-a-non-empty-directory-on-the-container). E.g. adding the `:Z` or `:z` flags where appropriate: `-v $PWD:/volume:Z`.

## Extending

### Extra C libraries

If you need extra C libraries, you can inherit from this image `FROM clux/muslrust:stable as builder` and add extra `curl` -> `make` instructions. We are unlikely to include other C libraries herein unless they are very popular.

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

## Alternatives

- `rustup target add x86_64-unknown-linux-musl` works locally when not needing [C libraries](#c-libraries)
- [official rust image](https://hub.docker.com/_/rust) can `target add` and easily cross-build when not needing [C libraries](#c-libraries)
- [cross](https://github.com/japaric/cross) can cross-build different embedded targets
