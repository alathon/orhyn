#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"

headless=0
zone_args=()

for arg in "$@"; do
    if [[ "$arg" == "--headless" ]]; then
        headless=1
    else
        zone_args+=("$arg")
    fi
done

has_option() {
    local value name

    for value in "${zone_args[@]}"; do
        for name in "$@"; do
            if [[ "$value" == "$name" ]]; then
                return 0
            fi
        done
    done

    return 1
}

if ! has_option "--zone" "--zone-name" "--zone-id"; then
    zone_args+=("--zone" "mvp")
fi

if ! has_option "--port"; then
    zone_args+=("--port" "4242")
fi

if ! has_option "--advertise-address"; then
    zone_args+=("--advertise-address" "127.0.0.1")
fi

if ! has_option "--orchestrator-url" "--orchestrator"; then
    zone_args+=("--orchestrator-url" "ws://127.0.0.1:9000/ws")
fi

if ! command -v "$godot_bin" >/dev/null 2>&1; then
    echo "Missing Godot executable: $godot_bin" >&2
    exit 127
fi

godot_args=("--path" "./godot")
if (( headless )); then
    godot_args+=("--headless")
else
    godot_args+=("--windowed")
fi

godot_args+=("--scene" "res://projects/game-server/src/main.tscn" "--")
godot_args+=("${zone_args[@]}")

cd "$project_root"
exec "$godot_bin" "${godot_args[@]}"
