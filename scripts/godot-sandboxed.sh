#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
runtime_dir="${ORHYN_GODOT_RUNTIME_DIR:-${TMPDIR:-/tmp}/orhyn-godot-runtime}"

if ! command -v "$godot_bin" >/dev/null 2>&1; then
    echo "Missing Godot executable: $godot_bin" >&2
    exit 127
fi

mkdir -p \
    "$runtime_dir/home" \
    "$runtime_dir/data" \
    "$runtime_dir/config" \
    "$runtime_dir/cache" \
    "$runtime_dir/logs"

has_log_file=0
for arg in "$@"; do
    if [[ "$arg" == "--log-file" || "$arg" == --log-file=* ]]; then
        has_log_file=1
        break
    fi
done

godot_args=()
if (( ! has_log_file )); then
    godot_args+=("--log-file" "$runtime_dir/logs/godot.log")
fi
godot_args+=("$@")

cd "$project_root"
HOME="$runtime_dir/home" \
XDG_DATA_HOME="$runtime_dir/data" \
XDG_CONFIG_HOME="$runtime_dir/config" \
XDG_CACHE_HOME="$runtime_dir/cache" \
exec "$godot_bin" "${godot_args[@]}"
