branch = $(shell git rev-parse --abbrev-ref HEAD)

.ONESHELL .PHONY: build up down test
.DEFAULT_GOAL := build

custom_ca:
ifdef CUSTOM_CA
	cp -rf $(CUSTOM_CA)/* ca_certificates/ || cp -f $(CUSTOM_CA) ca_certificates/
endif

build: custom_ca
	docker build . -t local/presto:$(branch)
	docker tag  local/presto:$(branch) local/presto:latest

## Not used yet
up:
	vagrant up
down:
	vagrant destroy
test:
	ANSIBLE_ARGS='--extra-vars "mode=test"' vagrant up --provision

