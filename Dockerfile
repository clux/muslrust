# syntax=docker/dockerfile:1
FROM ubuntu:noble
SHELL ["/bin/bash", "-eux", "-o", "pipefail", "-c"]

LABEL maintainer="Eirik Albrigtsen <sszynrae@gmail.com>"
LABEL org.opencontainers.image.create="$(date --utc --iso-8601=seconds)"
LABEL org.opencontainers.image.documentation="https://github.com/clux/muslrust"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.url="https://github.com/clux/muslrust"
LABEL org.opencontainers.image.description="Docker environment for building musl based static rust binaries"

# Required packages:
# - musl-dev, musl-tools - the musl toolchain
# - curl, g++, make, pkgconf, cmake - for fetching and building third party libs
# - ca-certificates - peer verification of downloads
# - git - cargo builds in user projects
# - file - needed by rustup.sh install
# - automake autoconf libtool - support crates building C deps as part cargo build
# NB: does not include cmake atm
RUN <<HEREDOC
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
HEREDOC

# Common arg for arch used in urls and triples
ARG AARCH
# Install rust using rustup
ARG CHANNEL
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse

ARG RUSTUP_VER="1.28.2"
ARG RUST_ARCH="${AARCH}-unknown-linux-gnu"
RUN <<HEREDOC
    curl -fsSL -o rustup-init "https://static.rust-lang.org/rustup/archive/${RUSTUP_VER}/${RUST_ARCH}/rustup-init"
    chmod +x rustup-init
    ./rustup-init -y --default-toolchain "${CHANNEL}" --profile minimal --no-modify-path
    rm rustup-init
    ~/.cargo/bin/rustup target add "${AARCH}-unknown-linux-musl"
HEREDOC

# Allow non-root access to cargo
RUN chmod a+X /root

# Convenience list of versions and variables for compilation later on
# This helps continuing manually if anything breaks.
ENV CC=musl-gcc \
    PREFIX=/musl \
    PATH=/usr/local/bin:/root/.cargo/bin:${PATH} \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    LD_LIBRARY_PATH=${PREFIX}

# Install a more recent release of protoc (protobuf-compiler in Ubuntu Noble is v21.12 from Dec 2022)
ARG PROTOBUF_VER="31.0"
RUN <<HEREDOC
    ASSET_NAME="protoc-${PROTOBUF_VER}-linux-$([ "${AARCH}" = "aarch64" ] && echo "aarch_64" || echo "{$AARCH}")"
    curl -fsSL -o /tmp/protoc.zip "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VER}/${ASSET_NAME}.zip"

    cd /tmp && unzip protoc.zip
    cp bin/protoc /usr/bin/protoc
    rm -rf *
HEREDOC

# Install prebuilt sccache based on platform
ARG SCCACHE_VER="0.10.0"
RUN <<HEREDOC
    ASSET_NAME="sccache-v${SCCACHE_VER}-${AARCH}-unknown-linux-musl"
    curl -fsSL "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VER}/${ASSET_NAME}.tar.gz" | tar -xz
    mv "${ASSET_NAME}/sccache" /usr/local/bin/
    chmod +x /usr/local/bin/sccache
    rm -rf sccache-v${SCCACHE_VER}-*-unknown-linux-musl
HEREDOC

# Build zlib
ARG ZLIB_VER="1.3.1"
RUN <<HEREDOC
    curl -fsSL "https://zlib.net/zlib-${ZLIB_VER}.tar.gz" | tar -xz
    cd "zlib-${ZLIB_VER}"

    CC="musl-gcc -fPIC -pie"
    CFLAGS="-I${PREFIX}/include"
    LDFLAGS="-L${PREFIX}/lib"
    ./configure --static --prefix="${PREFIX}"
    make -j$(nproc) && make install

    cd .. && rm -rf "zlib-${ZLIB_VER}"
HEREDOC

# Build libsqlite3 using same configuration as the alpine linux main/sqlite package
ARG SQLITE_VER="3490200"
RUN <<HEREDOC
    curl -fsSL "https://www.sqlite.org/2025/sqlite-autoconf-${SQLITE_VER}.tar.gz" | tar -xz
    cd "sqlite-autoconf-${SQLITE_VER}"

    CC="musl-gcc -fPIC -pie"
    CFLAGS="-DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_RTREE -DSQLITE_USE_URI -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_JSON1"
    ./configure --prefix="${PREFIX}" --host=x86_64-unknown-linux-musl --enable-threadsafe --disable-shared
    make && make install

    cd .. && rm -rf "sqlite-autoconf-${SQLITE_VER}"
HEREDOC

ENV PATH=/root/.cargo/bin:${PREFIX}/bin:${PATH} \
    RUSTUP_HOME=/root/.rustup \
    CARGO_BUILD_TARGET=${AARCH}-unknown-linux-musl \
    CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUSTFLAGS="-Clink-self-contained=yes -Clinker=rust-lld -Ctarget-feature=+crt-static" \
    PKG_CONFIG_ALLOW_CROSS=true \
    PKG_CONFIG_ALL_STATIC=true \
    PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PG_CONFIG_AARCH64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    # Rust libz-sys support
    LIBZ_SYS_STATIC=1 \
    ZLIB_STATIC=1 \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

# Allow ditching the -w /volume flag to docker run
WORKDIR /volume
