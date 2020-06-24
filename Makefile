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
# start commands
up: clean update-box
	SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} vagrant up --provision

update-box:
	@SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} vagrant box update || (echo '\n\nIf you get an SSL error you might be behind a transparent proxy. \nMore info https://github.com/fredrikhgrelland/vagrant-hashistack/blob/master/README.md#if-you-are-behind-a-transparent-proxy\n\n' && exit 2)

test: clean update-box
	ANSIBLE_ARGS='--extra-vars "mode=test"' SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} vagrant up --provision

# clean commands
destroy-box:
	vagrant destroy -f

remove-tmp:
	rm -rf ./tmp

clean: destroy-box remove-tmp