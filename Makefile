# Strict as the repository's scripts are, which make's default /bin/sh is not.
SHELL := bash
.SHELLFLAGS := -Eeuo pipefail -O inherit_errexit -O failglob -c

# --profile test so the shell and shell_test services are built here rather than
# on demand by the --build the other targets carry.
build:
	docker/build-compose --profile test
# In shell_test, as make test runs, which mounts nothing: the report leaves it
# as a tar on stdout, which bin/coverage --extract unpacks on the host into
# tmp/coverage/. Built first rather than with run --build, whose progress would
# go to stdout too; -T, so no terminal mangles the stream.
coverage:
	docker compose --profile test build shell_test
	docker compose --profile test run --rm -T shell_test coverage --tar $(TESTS) \
		| bin/coverage --extract
format:
	docker compose --profile test run --rm --build shell format
lint:
	docker compose --profile test run --rm --build shell_test lint
test:
	docker compose --profile test run --rm --build shell_test test $(TESTS)
upgrade-pre:
	docker/upgrade --record tmp/upgrade.record Dockerfile .github/workflows/*.yml \
		github/review/action.yml
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
