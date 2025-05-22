
[private]
default:
  @just --list --unsorted --color=always

_build channel platform:
	docker build --build-arg CHANNEL="{{channel}}" --platform="{{platform}}" -t rustmusl-temp . -f Dockerfile
# Build the stable x86 container
build-stable-amd: (_build "stable" "linux/amd64")
# Build the nightly x86 container
build-nightly-amd: (_build "nightly" "linux/amd64")
# Build the stable arm container
build-stable-arm: (_build "stable" "linux/arm64")
# Build the nightly arm container
build-nightly-arm: (_build "nightly" "linux/arm64")

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
    ./test.sh {{crate}}
_t_macos_aarch64 crate:
    #!/bin/bash
    export PLATFORM="linux/arm64"
    export TARGET_DIR="aarch64-unknown-linux-musl"
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
  docker builder prune --all

# Cleanup test artifacts
clean-tests:
  sudo find . -iname Cargo.lock -exec rm {} \;
  sudo find . -mindepth 3 -maxdepth 3 -name target -exec rm -rf {} \;
  sudo rm -f test/dieselsqlitecrate/main.db
