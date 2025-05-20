
[private]
default:
  @just --list --unsorted --color=always

_build channel ar platform ext:
	docker build --build-arg CHANNEL="{{channel}}" --build-arg AR="{{ar}}" --platform="{{platform}}" -t rustmusl-temp . -f Dockerfile.{{ext}}
# Build the stable x86 container
build-stable-amd: (_build "stable" "amd64" "linux/amd64" "x86_64")
# Build the nightly x86 container
build-nightly-amd: (_build "nightly" "amd64" "linux/amd64" "x86_64")
# Build the stable arm container
build-stable-arm: (_build "stable" "arm64" "linux/arm64" "arm64")
# Build the nightly arm container
build-nightly-arm: (_build "nightly" "arm64" "linux/arm64" "arm64")

# Shell into the built container
run:
	docker run -v $PWD/test:/volume  -w /volume -it rustmusl-temp /bin/bash

# Build test runner
test-setup:
    docker build -t test-runner . -f Dockerfile.test-runner

# Test an individual crate against built container
_t crate:
    ./test.sh {{crate}}

# Test an individual crate locally using env vars set by _t_amd or t_arm
_ti crate:
    # poor man's environment multiplex
    just _t_{{ os() }}_{{ arch() }} {{crate}}

# when running locally we can use one of these instead of _t
_t_linux_x86_64 crate:
    #!/bin/bash
    export PLATFORM="linux/amd64"
    export TARGET_DIR="x86_64-unknown-linux-musl"
    export AR="amd64"
    ./test.sh {{crate}}
_t_macos_aarch64 crate:
    #!/bin/bash
    export PLATFORM="linux/arm64"
    export TARGET_DIR="aarch64-unknown-linux-musl"
    export AR="arm64"
    ./test.sh {{crate}}

# Test all crates against built container locally
test: (_ti "plain") (_ti "serde") (_ti "zlib") (_ti "hypertls") (_ti "dieselsqlite")
# Test all crates against built container in ci (inheriting set PLATFORM/TARGET_DIR/AR vars)
test-ci: (_t "plain") (_t "serde") (_t "zlib") (_t "hypertls") (_t "dieselsqlite")

# Cleanup everything
clean: clean-docker clean-tests

# Cleanup docker images with clux/muslrus_t name
clean-docker:
  docker images clux/muslrust -q | xargs -r docker rmi -f

# Cleanup test artifacts
clean-tests:
  sudo find . -iname Cargo.lock -exec rm {} \;
  sudo find . -mindepth 3 -maxdepth 3 -name target -exec rm -rf {} \;
  sudo rm -f test/dieselsqlitecrate/main.db
