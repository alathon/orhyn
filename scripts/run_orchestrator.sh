#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
go_bin="${GO_BIN:-go}"
orchestrator_path="$project_root/orchestrator"
build_path="$orchestrator_path/.bin"
exe_path="$build_path/orchestrator"

if ! command -v "$go_bin" >/dev/null 2>&1; then
    echo "Missing Go executable: $go_bin" >&2
    exit 127
fi

mkdir -p "$build_path"
cd "$orchestrator_path"
"$go_bin" build -o "$exe_path" ./cmd/orchestrator
exec "$exe_path" "$@"
