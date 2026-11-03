# Strict as the repository's scripts are, which make's default /bin/sh is not.
SHELL := bash
.SHELLFLAGS := -Eeuo pipefail -O inherit_errexit -O failglob -c

# --profile test so the shell and shell_test services are built here rather than
# on demand by the --build the other targets carry.
build:
	docker/build-compose --profile test
# The shell service, since its mount is the one that lets the report reach
# tmp/coverage/ on the host.
coverage:
	docker compose --profile test run --rm --build shell coverage $(TESTS)
format:
	docker compose --profile test run --rm --build shell format
lint:
	docker compose --profile test run --rm --build shell_test lint
test:
	docker compose --profile test run --rm --build shell_test test $(TESTS)
upgrade-pre:
	docker/upgrade --record tmp/upgrade.record Dockerfile .github/workflows/*.yml
# One step at a time even under -j, since each needs the one before it done.
upgrade:
	$(MAKE) upgrade-pre
	$(MAKE) upgrade-post
# Alone, it finishes an upgrade whose build or tests failed, once fixed.
upgrade-post:
	$(MAKE) build
	$(MAKE) test
	docker/upgrade-commit tmp/upgrade.record
# On the host rather than in the image, since it asks on the terminal and
# pushes.
workflows-approve:
	github/workflows-approve
.PHONY: build coverage format lint test upgrade-pre upgrade upgrade-post \
	workflows-approve
