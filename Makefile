DC = docker compose --profile tools run --rm --build

# --profile tools so the format and test services are built here rather than on
# demand by the --build the gates carry.
build:
	docker/build-compose --profile tools
format:
	$(DC) format
lint:
	$(DC) test lint
test:
	$(DC) test test $(TESTS)
upgrade-pre:
	docker/upgrade
# One step at a time even under -j, since each needs the one before it done.
upgrade:
	$(MAKE) upgrade-pre
	$(MAKE) build
	$(MAKE) format
	$(MAKE) test
.PHONY: build format lint test upgrade-pre upgrade
