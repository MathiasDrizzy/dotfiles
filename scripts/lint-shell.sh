#!/usr/bin/env bash
# Lints every tracked shell script with shellcheck and shfmt, using pinned tool versions.
# CI and verificar.sh run this same script. Needs `uvx` (uv) and `go` on the PATH.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SHELLCHECK_PY_VERSION="0.11.0.1" # ships ShellCheck 0.11.0
SHFMT_VERSION="v3.14.1"

files=()
while IFS= read -r f; do files+=("$f"); done < <(git ls-files '*.sh' 'scripts/hooks/*')

echo "==> shellcheck (shellcheck-py ${SHELLCHECK_PY_VERSION})"
uvx --quiet --from "shellcheck-py==${SHELLCHECK_PY_VERSION}" shellcheck "${files[@]}"
echo "==> shfmt ${SHFMT_VERSION}"
go run "mvdan.cc/sh/v3/cmd/shfmt@${SHFMT_VERSION}" -d "${files[@]}"
