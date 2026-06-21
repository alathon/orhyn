#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
log_dir="${ORHYN_LOG_DIR:-$project_root/logs}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"

source "$script_dir/lib/process_supervisor.sh"

headless=0
for arg in "$@"; do
    if [[ "$arg" == "--headless" ]]; then
        headless=1
    fi
done

get_primary_geometry() {
    local geometry

    if ! command -v xrandr >/dev/null 2>&1; then
        return 1
    fi

    geometry="$(
        xrandr --current 2>/dev/null | awk '
            / connected primary / { print $4; exit }
            / connected / {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+$/) {
                        print $i
                        exit
                    }
                }
            }
        '
    )"

    [[ -n "$geometry" ]] || return 1
    printf '%s\n' "$geometry"
}

new_godot_zone_args() {
    local zone_name="$1"
    local port="$2"
    local x="$3"
    local y="$4"
    shift 4

    godot_args=("--path" "./godot")

    if (( headless )); then
        godot_args+=("--headless")
    else
        godot_args+=("--windowed" "--position" "$x,$y")
    fi

    godot_args+=(
        "--scene" "res://projects/game-server/src/main.tscn"
        "--"
        "--zone" "$zone_name"
        "--port" "$port"
        "--advertise-address" "127.0.0.1"
        "--orchestrator-url" "ws://127.0.0.1:9000/ws"
    )
}

if ! command -v "$godot_bin" >/dev/null 2>&1; then
    echo "Missing Godot executable: $godot_bin" >&2
    exit 127
fi

mkdir -p "$log_dir"
supervisor_install_traps

supervisor_start \
    "orchestrator" \
    "$log_dir/run_servers-$run_id-orchestrator.log" \
    "$project_root" \
    "$script_dir/run_orchestrator.sh" \
    "--default-zone" "mvp" \
    "--game-server-port" "9000" \
    "--client-port" "9001" \
    "--health-port" "9100"

sleep 0.75

mvp_x=80
forest_x=1240
zone_y=40

if (( ! headless )); then
    if geometry="$(get_primary_geometry)"; then
        if [[ "$geometry" =~ ^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$ ]]; then
            screen_left="${BASH_REMATCH[3]}"
            screen_width="${BASH_REMATCH[1]}"
            screen_top="${BASH_REMATCH[4]}"
            estimated_window_width=1152

            mvp_x=$((screen_left + 80))
            forest_x=$((screen_left + screen_width - estimated_window_width - 80))
            zone_y=$((screen_top + 40))
        fi
    fi
fi

godot_args=()
new_godot_zone_args "mvp" "4242" "$mvp_x" "$zone_y"
supervisor_start \
    "zone:mvp" \
    "$log_dir/run_servers-$run_id-zone-mvp.log" \
    "$project_root" \
    "$godot_bin" \
    "${godot_args[@]}"

godot_args=()
new_godot_zone_args "forest" "4243" "$forest_x" "$zone_y"
supervisor_start \
    "zone:forest" \
    "$log_dir/run_servers-$run_id-zone-forest.log" \
    "$project_root" \
    "$godot_bin" \
    "${godot_args[@]}"

echo "Streaming output. Press Ctrl-C to stop orchestrator and all zones."

set +e
supervisor_wait
status="$?"
set -e

trap - EXIT
supervisor_stop_all
exit "$status"
