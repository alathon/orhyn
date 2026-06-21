#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
log_dir="${ORHYN_LOG_DIR:-$project_root/logs}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"

source "$script_dir/lib/process_supervisor.sh"

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

if ! command -v "$godot_bin" >/dev/null 2>&1; then
    echo "Missing Godot executable: $godot_bin" >&2
    exit 127
fi

mkdir -p "$log_dir"
supervisor_install_traps

inset_x=80
inset_y=40
estimated_window_width=1152
estimated_window_height=648
screen_left=0
screen_top=0
screen_width=1920
screen_height=1080

if geometry="$(get_primary_geometry)"; then
    if [[ "$geometry" =~ ^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$ ]]; then
        screen_width="${BASH_REMATCH[1]}"
        screen_height="${BASH_REMATCH[2]}"
        screen_left="${BASH_REMATCH[3]}"
        screen_top="${BASH_REMATCH[4]}"
    fi
fi

left_x=$((screen_left + inset_x))
right_x=$((screen_left + screen_width - estimated_window_width - inset_x))
top_y=$((screen_top + inset_y))
bottom_y=$((screen_top + screen_height - estimated_window_height - inset_y))

supervisor_start \
    "server" \
    "$log_dir/run_server_and_client-$run_id-server.log" \
    "$project_root" \
    "$godot_bin" \
    "--path" "./godot" \
    "--windowed" \
    "--position" "$left_x,$top_y" \
    "--scene" "res://projects/game-server/src/main.tscn" \
    "--" \
    "--zone" "mvp" \
    "--port" "4242" \
    "--advertise-address" "127.0.0.1" \
    "--orchestrator-url" "ws://127.0.0.1:9000/ws"

sleep 0.5

supervisor_start \
    "client:1" \
    "$log_dir/run_server_and_client-$run_id-client-1.log" \
    "$project_root" \
    "$godot_bin" \
    "--path" "./godot" \
    "--windowed" \
    "--position" "$right_x,$top_y" \
    "--scene" "res://projects/client/src/client_app.tscn"

supervisor_start \
    "client:2" \
    "$log_dir/run_server_and_client-$run_id-client-2.log" \
    "$project_root" \
    "$godot_bin" \
    "--path" "./godot" \
    "--windowed" \
    "--position" "$left_x,$bottom_y" \
    "--scene" "res://projects/client/src/client_app.tscn"

supervisor_start \
    "client:3" \
    "$log_dir/run_server_and_client-$run_id-client-3.log" \
    "$project_root" \
    "$godot_bin" \
    "--path" "./godot" \
    "--windowed" \
    "--position" "$right_x,$bottom_y" \
    "--scene" "res://projects/client/src/client_app.tscn"

echo "Streaming output. Press Ctrl-C to stop server and all clients."

set +e
supervisor_wait
status="$?"
set -e

trap - EXIT
supervisor_stop_all
exit "$status"
