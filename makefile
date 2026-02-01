# Check to see if we can use ash, in Alpine images, or default to BASH.
SHELL_PATH = /bin/ash
SHELL = $(if $(wildcard $(SHELL_PATH)),/bin/ash,/bin/bash)

# RSA Keys
# 	To generate a private/public key PEM file.
# 	$ openssl genpkey -algorithm RSA -out private.pem -pkeyopt rsa_keygen_bits:2048
# 	$ openssl rsa -pubout -in private.pem -out public.pem

run:
	go run apis/services/sales/main.go | go run apis/tooling/logfmt/main.go

help: 
	go run apis/services/sales/main.go --help

version: 
	go run apis/services/sales/main.go --version

curl-test:
	curl -il -X GET http://localhost:3000/test

curl-live:
	curl -il -X GET http://localhost:3000/liveness

curl-ready:
	curl -il -X GET http://localhost:3000/readiness

curl-error:
	curl -il -X GET http://localhost:3000/testerror

curl-panic:
	curl -il -X GET http://localhost:3000/testpanic

admin:
	go run apis/tooling/admin/main.go

# admin-token
# export TOKEN=eyJhbGciOiJSUzI1NiIsImtpZCI6IjU0YmIyMTY1LTcxZTEtNDFhNi1hZjNlLTdkYTRhMGUxZTJjMSIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzZXJ2aWNlIHByb2plY3QiLCJzdWIiOiI0OGUxYzNlNy00MGNlLTRjMTYtOTllNC04MzEwYjA5MzZkYmEiLCJleHAiOjE4MDE0NTM3MzksImlhdCI6MTc2OTkxNzczOSwiUm9sZXMiOlsiQURNSU4iXX0.FnHLDC_4TdeYFwIrWVqtgdwAZr_2pBidLJZtV29CGcGss58KzXiTlJLo8RYZke9V09ZVgLFFIdSU-yQqg426Uu8NK1ucDpxB1LBnurW2Ja5g_Ip2nwBG5gjDpnBWHrc-eN4hcz4_5Pa16fQTeM82WStGh5TR4akXoQa0Fpk7DgnP3CmElY5d09cPVY6sNOjpwQXW5MFVQ6gefYG6TqA-0X61UZGgnYCFTBAa3oxB2ee7_kADotZtxXNEwa2x1V8PYavApjfo08YyhDM5ITc3PntEtES-TfouqEYH6RPUXdwLGWs-YP9j68x0_YECedEa2nYSzUZnbxH4c23Xt9Nfow

curl-auth:
	curl -il \
	-H "Authorization: Bearer ${TOKEN}" "http://localhost:3000/testauth"
# ==============================================================================
# Define dependencies

GOLANG          := golang:1.25
ALPINE          := alpine:3.23
KIND            := kindest/node:v1.35.0
POSTGRES        := postgres:18.1
GRAFANA         := grafana/grafana:12.3.0
PROMETHEUS      := prom/prometheus:v3.8.0
TEMPO           := grafana/tempo:2.9.0
LOKI            := grafana/loki:3.6.0
PROMTAIL        := grafana/promtail:3.6.0

KIND_CLUSTER    := ardan-starter-cluster
NAMESPACE       := sales-system
SALES_APP       := sales
AUTH_APP        := auth
BASE_IMAGE_NAME := localhost/ardanlabs
VERSION         := 0.0.1
SALES_IMAGE     := $(BASE_IMAGE_NAME)/$(SALES_APP):$(VERSION)
METRICS_IMAGE   := $(BASE_IMAGE_NAME)/metrics:$(VERSION)
AUTH_IMAGE      := $(BASE_IMAGE_NAME)/$(AUTH_APP):$(VERSION)

# ==============================================================================
# Detect operating system and set the appropriate open command

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	OPEN_CMD := open
else
	OPEN_CMD := xdg-open
endif

# ==============================================================================
# Building containers

build: sales

sales:
	docker build \
		-f zarf/docker/dockerfile.sales \
		-t $(SALES_IMAGE) \
		--build-arg BUILD_TAG=$(VERSION) \
		--build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
		.


# ==============================================================================
# Running from within k8s/kind
# Docker Desktop 28.3.2 changed how it stores image layers, causing KIND's kind
# load docker-image command to fail with "content digest not found" errors. The
# workaround uses docker save | docker exec to bypass this incompatibility for
# the critical images allowing this to work without a network.

dev-up:
	kind create cluster \
		--image $(KIND) \
		--name $(KIND_CLUSTER) \
		--config zarf/k8s/dev/kind-config.yaml

	kubectl wait --timeout=120s --namespace=local-path-storage --for=condition=Available deployment/local-path-provisioner

dev-down:
	kind delete cluster --name $(KIND_CLUSTER)

dev-status-all:
	kubectl get nodes -o wide
	kubectl get svc -o wide
	kubectl get pods -o wide --watch --all-namespaces

dev-status:
	watch -n 2 kubectl get pods -o wide --all-namespaces

# ------------------------------------------------------------------------------

dev-load:
	kind load docker-image $(SALES_IMAGE) --name $(KIND_CLUSTER)

dev-apply:
	kustomize build zarf/k8s/dev/sales | kubectl apply -f -
	kubectl wait pods --namespace=$(NAMESPACE) --selector app=$(SALES_APP) --timeout=120s --for=condition=Ready

dev-restart:
	kubectl rollout restart deployment $(SALES_APP) --namespace=$(NAMESPACE)

dev-run: build dev-up dev-load dev-apply

dev-update: build dev-load dev-restart

dev-update-apply: build dev-load dev-apply

dev-logs:
	kubectl logs --namespace=$(NAMESPACE) -l app=$(SALES_APP) --all-containers=true -f --tail=100 --max-log-requests=6 | go run apis/tooling/logfmt/main.go -service=$(SALES_APP)

# ------------------------------------------------------------------------------

dev-describe-deployment:
	kubectl describe deployment --namespace=$(NAMESPACE) $(SALES_APP)

dev-describe-sales:
	kubectl describe pod --namespace=$(NAMESPACE) -l app=$(SALES_APP)

# ==============================================================================
# Metrics and Tracing

metrics:
	expvarmon -ports="localhost:3010" -vars="build,requests,goroutines,errors,panics,mem:memstats.HeapAlloc,mem:memstats.HeapSys,mem:memstats.Sys"

statsviz:
	$(OPEN_CMD) http://localhost:3010/debug/statsviz

# ==============================================================================
# Modules support

tidy:
	go mod tidy
	go mod vendor

# ==============================================================================
# Running tests within the local computer

test-down:
	docker stop servicetest
	docker rm servicetest -v

test-r:
	CGO_ENABLED=1 go test -race -count=1 ./...

test-only:
	CGO_ENABLED=0 go test -count=1 ./...

lint:
	CGO_ENABLED=0 go vet ./...
	staticcheck -checks=all ./...

vuln-check:
	govulncheck ./...

test: test-only lint vuln-check

test-race: test-r lint vuln-check