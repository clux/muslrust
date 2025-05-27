#!/bin/bash
set -ex -o pipefail

# Common vars:
CRATE_NAME="${1}crate"
CRATE_PATH="./test/${CRATE_NAME}"

# Build and verify successful static compilation of a crate:
function docker_build() {
  echo "Target dir: ${TARGET_DIR}"
  echo "Platform: ${PLATFORM}"

  # NB: add -vv to cargo build when debugging
  docker run --rm -it \
    --env RUST_BACKTRACE=1 \
    --volume "${CRATE_PATH}:/volume" \
    --volume cargo-cache:/opt/cargo/registry \
    --platform "${PLATFORM}" \
    rustmusl-temp \
    cargo build

  # Verify the build artifact works and is statically linked:
  # (A container is used for `ldd` so that a non-native platform can also be tested)
  local CRATE_ARTIFACT="./target/${TARGET_DIR}/debug/${CRATE_NAME}"
  docker run --rm -it \
    --env RUST_BACKTRACE=1 \
    --volume "${CRATE_PATH}:/volume" \
    --workdir /volume \
    --platform "${PLATFORM}" \
    test-runner \
    bash -ex -c "
      '${CRATE_ARTIFACT}'
      ldd '${CRATE_ARTIFACT}' 2>&1 \
        | grep -qE 'not a dynamic|statically linked' \
        && echo '${CRATE_NAME} is a static executable'
    "
}

# Reference - Helpers to locally compare builds from alternative images (x86_64 arch only):
# - https://github.com/emk/rust-musl-builder (ss1, abandoned)
# - https://gitlab.com/rust_musl_docker/image (ss1, abandoned)
# - https://github.com/BlackDex/rust-musl (active, supports ssl 3.X)
function docker_build_other_image() {
  docker run --rm -it \
    --env RUST_BACKTRACE=1 \
    --volume "${CRATE_PATH}:/home/rust/src" \
    --volume cargo-cache:/home/rust/.cargo \
    blackdex/rust-musl:x86_64-musl-stable \
    cargo build -vv

    check_crate_build_locally
}

# Verify the build artifact works and is statically linked:
function check_crate_build_locally() {
  local CRATE_ARTIFACT="${CRATE_PATH}/target/x86_64-unknown-linux-musl/debug/${CRATE_NAME}"

  "${CRATE_ARTIFACT}"
  ldd "${CRATE_ARTIFACT}" 2>&1 \
    | grep -qE 'not a dynamic|statically linked' \
    && echo "${CRATE_NAME} is a static executable"
}

docker_build
