# --profile test so the shell and shell_test services are built here rather than
# on demand by the --build the other targets carry.
build:
	docker/build-compose --profile test
format:
	docker compose --profile test run --rm --build shell format
lint:
	docker compose --profile test run --rm --build shell_test lint
test:
	docker compose --profile test run --rm --build shell_test test $(TESTS)
upgrade-pre:
	docker/upgrade
# One step at a time even under -j, since each needs the one before it done.
upgrade:
	$(MAKE) upgrade-pre
	$(MAKE) build
	$(MAKE) test
.PHONY: build format lint test upgrade-pre upgrade
