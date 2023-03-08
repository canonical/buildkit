prefix=/usr/local
bindir=$(prefix)/bin

binaries: FORCE
	hack/binaries

images: FORCE
# canonical/buildkit:local and canonical/buildkit:local-rootless are created on Docker
	hack/images local canonical/buildkit
	TARGET=rootless hack/images local canonical/buildkit

install: FORCE
	mkdir -p $(DESTDIR)$(bindir)
	install bin/* $(DESTDIR)$(bindir)

clean: FORCE
	rm -rf ./bin

test:
	./hack/test integration gateway dockerfile

lint:
	./hack/lint

validate-vendor:
	./hack/validate-vendor

validate-shfmt:
	./hack/validate-shfmt

shfmt:
	./hack/shfmt

validate-generated-files:
	./hack/validate-generated-files

validate-all: test lint validate-vendor validate-generated-files

vendor:
	./hack/update-vendor

generated-files:
	./hack/update-generated-files

.PHONY: vendor generated-files test binaries images install clean lint validate-all validate-vendor validate-generated-files
FORCE:
