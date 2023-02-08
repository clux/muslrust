# See https://just.systems/man/

default:
  @just --list --unsorted --color=always | rg -v "    default"

_build channel:
  docker build --build-arg CHANNEL="{{channel}}" -t clux/muslrust:temp .
# Build the stable container locally tagged as :temp
build-stable: (_build "stable")
# Build the nightly container locally tagged as :temp
build-nightly: (_build "nightly")

# Shell into the built container
run:
  docker run -v $PWD/test:/volume  -w /volume -it clux/muslrust:temp /bin/bash

# Test an individual crate against built containr
_t crate:
    ./test.sh {{crate}}

# Test all crates against built container
test: (_t "plain") (_t "ssl") (_t "rustls") (_t "pq") (_t "serde") (_t "curl") (_t "zlib") (_t "hyper") (_t "dieselpg") (_t "dieselsqlite")

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

# mode: makefile
# End:
# vim: set ft=make :
