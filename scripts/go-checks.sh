#!/usr/bin/env bash
# Go checks for mac/tools/herdr-ctl with pinned tool versions. CI and verificar.sh run this same script.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../mac/tools/herdr-ctl"

GOLANGCI_LINT_VERSION="v2.14.0"
GOVULNCHECK_VERSION="v1.9.0"

echo "==> go vet"
go vet ./...
echo "==> go test -race"
go test -race -count=1 ./...
echo "==> golangci-lint ${GOLANGCI_LINT_VERSION}"
go run "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}" run ./...
echo "==> govulncheck ${GOVULNCHECK_VERSION}"
go run "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}" ./...
