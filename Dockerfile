# syntax=docker/dockerfile:1
ARG BASE_IMAGE=ubuntu:noble

# Mapping ARM64 / AMD64 naming conventions to equivalent `uname -a` output (build target specific):
FROM ${BASE_IMAGE} AS base-amd64
ENV DOCKER_TARGET_ARCH=x86_64
FROM ${BASE_IMAGE} AS base-arm64
ENV DOCKER_TARGET_ARCH=aarch64

FROM base-${TARGETARCH} AS base
SHELL ["/bin/bash", "-eux", "-o", "pipefail", "-c"]
# Required packages:
# - musl-dev, musl-tools - the musl toolchain
# - curl, g++, make, pkgconf, cmake - for fetching and building third party libs
# - ca-certificates - peer verification of downloads
# - git - cargo builds in user projects
# - file - needed by rustup.sh install
# - automake autoconf libtool - support crates building C deps as part cargo build
# NB: does not include cmake atm
RUN <<EOF
    apt-get update
    apt-get install --no-install-recommends -y \
        musl-dev \
        musl-tools \
        file \
        git \
        openssh-client \
        make \
        cmake \
        g++ \
        curl \
        pkgconf \
        ca-certificates \
        automake \
        autoconf \
        libtool \
        libprotobuf-dev \
        unzip

    rm -rf /var/lib/apt/lists/*
EOF

# Install a more recent release of protoc:
# renovate: datasource=github-releases depName=protocolbuffers/protobuf versioning=semver-coerced
ARG PB_VERSION="v33.4"
RUN <<EOF
    if [[ ${DOCKER_TARGET_ARCH} == 'aarch64' ]]; then
      DOCKER_TARGET_ARCH=aarch_64
    fi

    ASSET_NAME="protoc-${PB_VERSION#v}-linux-${DOCKER_TARGET_ARCH}"
    curl -fsSL -o protoc.zip "https://github.com/protocolbuffers/protobuf/releases/download/v${PB_VERSION#v}/${ASSET_NAME}.zip"

    unzip -j -d /usr/local/bin protoc.zip bin/protoc
    rm -rf protoc.zip
EOF

# Install prebuilt sccache based on platform:
# renovate: datasource=github-releases depName=mozilla/sccache
ARG SCCACHE_VERSION="0.12.0"
RUN <<EOF
    ASSET_NAME="sccache-v${SCCACHE_VERSION}-${DOCKER_TARGET_ARCH}-unknown-linux-musl"
    curl -fsSL "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/${ASSET_NAME}.tar.gz" \
      | tar -xz -C /usr/local/bin --strip-components=1 --no-same-owner "${ASSET_NAME}/sccache"
EOF

# Convenience list of variables for later compilation stages.
# This helps continuing manually if anything breaks.
ENV CC=musl-gcc \
    PREFIX=/musl \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Build zlib
FROM base AS build-zlib
# renovate: datasource=github-releases depName=madler/zlib
ARG ZLIB_VERSION="1.3.1"
WORKDIR /src/zlib
RUN <<EOF
    curl -fsSL "https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz" | tar -xz --strip-components=1

    export CC="musl-gcc -fPIC -pie"
    export CFLAGS="-I${PREFIX}/include"
    export LDFLAGS="-L${PREFIX}/lib"

    ./configure --static --prefix="${PREFIX}"
    make -j$(nproc) && make install
EOF

# Build libsqlite3 using same configuration as the alpine linux main/sqlite package
FROM base AS build-sqlite
# renovate: datasource=github-tags packageName=sqlite/sqlite versioning=semver-coerced
ARG SQLITE_VERSION="3.49.2"
WORKDIR /src/sqlite
RUN <<EOF
    # see product names and info at https://sqlite.org/download.html for why this line constructs the tarball name from a semver version
    SQL_ID="$(echo -n "${SQLITE_VERSION}" | xargs -d '.' printf '%d%02d%02d00')"
    curl -fsSL "https://www.sqlite.org/2025/sqlite-autoconf-${SQL_ID}.tar.gz" | tar -xz --strip-components=1

    export CC="musl-gcc -fPIC -pie"
    export CFLAGS="-DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_RTREE -DSQLITE_USE_URI -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_JSON1"

    ./configure --prefix="${PREFIX}" --host=x86_64-unknown-linux-musl --enable-threadsafe --disable-shared
    make && make install
EOF

# Install rust using rustup
FROM base AS install-rustup
ARG CHANNEL
# Use specific version of Rustup:
# https://github.com/clux/muslrust/pull/63
# renovate: datasource=github-tags packageName=rust-lang/rustup
ARG RUSTUP_VERSION=1.28.2
# Better support for running container user as non-root:
# https://github.com/clux/muslrust/pull/101
# Uses `--no-modify-path` as `PATH` is set explicitly
ENV RUSTUP_HOME=/opt/rustup
ENV CARGO_HOME=/opt/cargo
RUN <<EOF
    RUST_ARCH="${DOCKER_TARGET_ARCH}-unknown-linux-gnu"
    curl -fsSL -o rustup-init "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${RUST_ARCH}/rustup-init"
    chmod +x rustup-init
    mkdir -p /opt/{cargo,rustup}

    ./rustup-init -y \
      --default-toolchain "${CHANNEL}" \
      --profile minimal \
      --no-modify-path \
      --target "${DOCKER_TARGET_ARCH}-unknown-linux-musl"

    rm rustup-init
EOF

FROM base AS release
COPY --link --from=install-rustup /opt /opt
COPY --link --from=build-zlib ${PREFIX} ${PREFIX}
COPY --link --from=build-sqlite ${PREFIX} ${PREFIX}

ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUSTFLAGS="-C link-self-contained=yes -C linker=rust-lld -C target-feature=+crt-static" \
    PKG_CONFIG_ALLOW_CROSS=true \
    PKG_CONFIG_ALL_STATIC=true \
    PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PG_CONFIG_AARCH64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    # Rust `libz-sys` support:
    LIBZ_SYS_STATIC=1 \
    ZLIB_STATIC=1 \
    # Better support for running container user as non-root:
    # https://github.com/clux/muslrust/pull/101
    CARGO_BUILD_TARGET=${DOCKER_TARGET_ARCH}-unknown-linux-musl \
    CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup \
    # PATH prepends:
    # - `/opt/cargo/bin` for `cargo` + `rustup`
    # - `${PREFIX}/bin` for `sqlite3`
    PATH=/opt/cargo/bin:${PREFIX}/bin:${PATH} \
    # Misc:
    DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

# Allow ditching the -w /volume flag to docker run
WORKDIR /volume

LABEL org.opencontainers.image.authors="Eirik Albrigtsen <sszynrae@gmail.com>"
LABEL org.opencontainers.image.documentation="https://github.com/clux/muslrust"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.url="https://github.com/clux/muslrust"
LABEL org.opencontainers.image.description="Docker environment for building musl based static rust binaries"

