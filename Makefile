SHELL := bash
.SHELLFLAGS := -Eeuo pipefail -O inherit_errexit -O failglob -c

build:
	docker/build-compose --profile test
# Built first, since run --build would print its progress into the tar on
# stdout; -T, so no terminal mangles the stream.
coverage:
	docker compose --profile test build tooling_test
	docker compose --profile test run --rm -T tooling_test coverage $(TESTS) \
		| runner/coverage --extract
format:
	runner/format-host --build -- tooling format
lint:
	docker compose --profile test run --rm --build -T tooling_test lint
test:
	docker compose --profile test run --rm --build -T tooling_test test $(TESTS)
upgrade-pre:
	docker/upgrade-guard tmp/upgrade.record
	docker/upgrade --record tmp/upgrade.record Dockerfile .github/workflows/*.yml \
		github/review.yml
# One step at a time even under -j, since each needs the one before it done.
upgrade:
	$(MAKE) upgrade-pre
	$(MAKE) upgrade-post
upgrade-post:
	$(MAKE) build
	$(MAKE) format
	$(MAKE) test
	docker/upgrade-commit tmp/upgrade.record .
upgrade-discard:
	docker/upgrade-discard tmp/upgrade.record
# On the host rather than in the image, since it asks on the terminal and
# pushes.
workflows-approve:
	github/workflows-approve
.PHONY: build coverage format lint test upgrade-pre upgrade upgrade-post \
	upgrade-discard workflows-approve
