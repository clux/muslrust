FROM ubuntu:jammy
LABEL maintainer="Eirik Albrigtsen <sszynrae@gmail.com>"

# Required packages:
# - musl-dev, musl-tools - the musl toolchain
# - curl, g++, make, pkgconf, cmake - for fetching and building third party libs
# - ca-certificates - openssl + curl + peer verification of downloads
# - xutils-dev - for openssl makedepend
# - libssl-dev and libpq-dev - for dynamic linking during diesel_codegen build process
# - git - cargo builds in user projects
# - linux-headers-amd64 - needed for building openssl 1.1 (stretch only)
# - file - needed by rustup.sh install
# - automake autoconf libtool - support crates building C deps as part cargo build
# NB: does not include cmake atm
RUN apt-get update && apt-get install -y \
  musl-dev \
  musl-tools \
  file \
  git \
  openssh-client \
  make \
  g++ \
  curl \
  pkgconf \
  ca-certificates \
  xutils-dev \
  libssl-dev \
  libpq-dev \
  automake \
  autoconf \
  libtool \
  --no-install-recommends && \
  rm -rf /var/lib/apt/lists/*

# Install rust using rustup
ARG CHANNEL
ENV RUSTUP_VER="1.24.3" \
    RUST_ARCH="x86_64-unknown-linux-gnu"
RUN curl "https://static.rust-lang.org/rustup/archive/${RUSTUP_VER}/${RUST_ARCH}/rustup-init" -o rustup-init && \
    chmod +x rustup-init && \
    ./rustup-init -y --default-toolchain ${CHANNEL} --profile minimal && \
    rm rustup-init && \
    ~/.cargo/bin/rustup target add x86_64-unknown-linux-musl && \
    echo "[build]\ntarget = \"x86_64-unknown-linux-musl\"" > ~/.cargo/config

# Allow non-root access to cargo
RUN chmod a+X /root
COPY etc/profile.d/cargo.sh /etc/profile.d/cargo.sh

# Convenience list of versions and variables for compilation later on
# This helps continuing manually if anything breaks.
ENV SSL_VER="1.1.1o" \
    CURL_VER="7.83.1" \
    ZLIB_VER="1.2.12" \
    PQ_VER="14.3" \
    SQLITE_VER="3380500" \
    CC=musl-gcc \
    PREFIX=/musl \
    PATH=/usr/local/bin:/root/.cargo/bin:$PATH \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    LD_LIBRARY_PATH=$PREFIX

# Set up a prefix for musl build libraries, make the linker's job of finding them easier
# Primarily for the benefit of postgres.
# Lastly, link some linux-headers for openssl 1.1 (not used herein)
RUN mkdir $PREFIX && \
    echo "$PREFIX/lib" >> /etc/ld-musl-x86_64.path && \
    ln -s /usr/include/x86_64-linux-gnu/asm /usr/include/x86_64-linux-musl/asm && \
    ln -s /usr/include/asm-generic /usr/include/x86_64-linux-musl/asm-generic && \
    ln -s /usr/include/linux /usr/include/x86_64-linux-musl/linux

# Build zlib (used in openssl and pq)
RUN curl -sSL https://zlib.net/zlib-$ZLIB_VER.tar.gz | tar xz && \
    cd zlib-$ZLIB_VER && \
    CC="musl-gcc -fPIC -pie" LDFLAGS="-L$PREFIX/lib" CFLAGS="-I$PREFIX/include" ./configure --static --prefix=$PREFIX && \
    make -j$(nproc) && make install && \
    cd .. && rm -rf zlib-$ZLIB_VER

# Build openssl (used in curl and pq)
# Would like to use zlib here, but can't seem to get it to work properly
# TODO: fix so that it works
RUN curl -sSL https://www.openssl.org/source/openssl-$SSL_VER.tar.gz | tar xz && \
    cd openssl-$SSL_VER && \
    ./Configure no-zlib no-shared -fPIC --prefix=$PREFIX --openssldir=$PREFIX/ssl linux-x86_64 && \
    env C_INCLUDE_PATH=$PREFIX/include make depend 2> /dev/null && \
    make -j$(nproc) && make install && \
    cd .. && rm -rf openssl-$SSL_VER

# Build curl (needs with-zlib and all this stuff to allow https)
# curl_LDFLAGS needed on stretch to avoid fPIC errors - though not sure from what
RUN curl -sSL https://curl.se/download/curl-$CURL_VER.tar.gz | tar xz && \
    cd curl-$CURL_VER && \
    CC="musl-gcc -fPIC -pie" LDFLAGS="-L$PREFIX/lib" CFLAGS="-I$PREFIX/include" ./configure \
      --enable-shared=no --with-zlib --enable-static=ssl --enable-optimize --prefix=$PREFIX \
      --with-ca-path=/etc/ssl/certs/ --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt --without-ca-fallback \
      --with-openssl && \
    make -j$(nproc) curl_LDFLAGS="-all-static" && make install && \
    cd .. && rm -rf curl-$CURL_VER

# Build libpq
RUN curl -sSL https://ftp.postgresql.org/pub/source/v$PQ_VER/postgresql-$PQ_VER.tar.gz | tar xz && \
    cd postgresql-$PQ_VER && \
    CC="musl-gcc -fPIE -pie" LDFLAGS="-L$PREFIX/lib" CFLAGS="-I$PREFIX/include" ./configure \
    --without-readline \
    --with-openssl \
    --prefix=$PREFIX --host=x86_64-unknown-linux-musl && \
    cd src/common && make -s -j$(nproc) all && make -s install && cd ../.. && \
    cd src/port && make -s -j$(nproc) all && make -s install && cd ../.. && \
    cd src/interfaces/libpq make -s -j$(nproc) all-static-lib && make -s install install-lib-static && \
    cd ../../bin/pg_config && make -j $(nproc) && make install && \
    cd .. && rm -rf postgresql-$PQ_VER

# Build libsqlite3 using same configuration as the alpine linux main/sqlite package
RUN curl -sSL https://www.sqlite.org/2022/sqlite-autoconf-$SQLITE_VER.tar.gz | tar xz && \
    cd sqlite-autoconf-$SQLITE_VER && \
    CFLAGS="-DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_RTREE -DSQLITE_USE_URI -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_JSON1" \
    CC="musl-gcc -fPIC -pie" \
    ./configure --prefix=$PREFIX --host=x86_64-unknown-linux-musl --enable-threadsafe --enable-dynamic-extensions --disable-shared && \
    make && make install && \
    cd .. && rm -rf sqlite-autoconf-$SQLITE_VER

# SSL cert directories get overridden by --prefix and --openssldir
# and they do not match the typical host configurations.
# The SSL_CERT_* vars fix this, but only when inside this container
# musl-compiled binary must point SSL at the correct certs (muslrust/issues/5) elsewhere
# Postgres bindings need vars so that diesel_codegen.so uses the GNU deps at build time
# but finally links with the static libpq.a at the end.
# It needs the non-musl pg_config to set this up with libpq-dev (depending on libssl-dev)
# See https://github.com/sgrif/pq-sys/pull/18
ENV PATH=$PREFIX/bin:$PATH \
    TARGET=x86_64_unknown_linux_musl \
    HOST=x86_64_unknown_linux_gnu \
    PKG_CONFIG_ALLOW_CROSS=true \
    PKG_CONFIG_ALL_STATIC=true \
    PQ_LIB_STATIC_X86_64_UNKNOWN_LINUX_MUSL=true \
    PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig \
    PKG_CONFIG_PATH_X86_64_UNKNOWN_LINUX_MUSL=$PREFIX/lib/pkgconfig \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_MUSL=/musl/bin/pg_config \
    OPENSSL_STATIC=true \
    OPENSSL_DIR=$PREFIX \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs \
    LIBZ_SYS_STATIC=1 \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

# Allow ditching the -w /volume flag to docker run
WORKDIR /volume
