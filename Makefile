SHELL := /bin/bash
RUST_CHANNEL="stable"
.SHELLFLAGS := -euo pipefail -c

.PHONY: build run test push

build:
	docker build --build-arg CHANNEL="${RUST_CHANNEL}" -t clux/muslrust .
run:
	docker run -v $$PWD/test:/volume  -w /volume -it clux/muslrust /bin/bash

test-plain:
	./test.sh plain
test-curl:
	./test.sh curl
test-serde:
	./test.sh serde
test-rocket:
	if [ -z "$$RUST_CHANNEL" ] || [ "$$RUST_CHANNEL" = "nightly" ]; then \
		./test.sh rocket; \
	fi
test-pq:
	./test.sh pq
test-dieselpg:
	./test.sh dieselpg
test-dieselsqlite:
	./test.sh dieselsqlite
test-ssl:
	./test.sh ssl
test-zlib:
	./test.sh zlib
test-hyper:
	./test.sh hyper

clean-docker:
	docker images clux/muslrust -q | xargs -r docker rmi -f
clean-lock:
	sudo find . -iname Cargo.lock -exec rm {} \;
clean-builds:
	sudo find . -mindepth 3 -maxdepth 3 -name target -exec rm -rf {} \;
	sudo rm -f test/dieselsqlitecrate/main.db
clean: clean-docker clean-lock clean-builds

test: test-plain test-ssl test-pq test-serde test-curl test-zlib test-hyper test-dieselpg test-dieselsqlite
.PHONY: test-plain test-ssl test-pq test-rocket test-serde test-curl test-zlib test-hyper test-dieselpg test-dieselsqlite
