#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
log_root="${ORHYN_LOG_DIR:-$project_root/logs}/e2e"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
artifact_dir="$log_root/$run_id"
zone_id="mvp"
username="e2e_boot"
suite_timeout_seconds="${ORHYN_E2E_TIMEOUT_SECONDS:-30}"

source "$script_dir/lib/process_supervisor.sh"

usage() {
    cat <<EOF
Usage: $0 [--zone ZONE_ID] [--username USERNAME] [--timeout SECONDS]

Runs the single-client gameplay suite followed by the two-client replication
suite against fresh orchestrator and zone processes. Artifacts are written
under logs/e2e/.
EOF
}

while (($# > 0)); do
    case "$1" in
        --zone|--zone-id)
            zone_id="${2:-}"
            shift 2
            ;;
        --username)
            username="${2:-}"
            shift 2
            ;;
        --timeout)
            suite_timeout_seconds="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$zone_id" ]]; then
    echo "Zone id cannot be empty." >&2
    exit 2
fi

if [[ -z "$username" ]]; then
    echo "Username cannot be empty." >&2
    exit 2
fi

if ! [[ "$suite_timeout_seconds" =~ ^[0-9]+$ ]] || (( suite_timeout_seconds <= 0 )); then
    echo "Timeout must be a positive integer number of seconds." >&2
    exit 2
fi

if ! command -v timeout >/dev/null 2>&1; then
    echo "Missing required command: timeout" >&2
    exit 127
fi

allocated_ports=()

allocate_port() {
    local candidate
    local existing
    local in_use

    for _attempt in {1..100}; do
        candidate=$((20000 + RANDOM % 25000))
        in_use=0
        for existing in "${allocated_ports[@]}"; do
            if [[ "$existing" == "$candidate" ]]; then
                in_use=1
                break
            fi
        done
        if (( in_use )); then
            continue
        fi
        if (: >"/dev/tcp/127.0.0.1/$candidate") >/dev/null 2>&1; then
            continue
        fi

        allocated_ports+=("$candidate")
        printf '%s\n' "$candidate"
        return 0
    done

    echo "Could not allocate a free TCP port." >&2
    return 1
}

wait_for_url() {
    local name="$1"
    local url="$2"
    local timeout_seconds="$3"
    local started

    started="$(date +%s)"
    while true; do
        if curl -fsS "$url" >/dev/null 2>&1; then
            return 0
        fi
        if (( $(date +%s) - started >= timeout_seconds )); then
            echo "Timed out waiting for $name at $url" >&2
            return 1
        fi
        sleep 0.2
    done
}

wait_for_zone_registration() {
    local url="$1"
    local expected_zone="$2"
    local timeout_seconds="$3"
    local started
    local body

    started="$(date +%s)"
    while true; do
        body="$(curl -fsS "$url" 2>/dev/null || true)"
        if [[ "$body" == *'"registered_zones":1'* && "$body" == *"\"$expected_zone\""* ]]; then
            return 0
        fi
        if (( $(date +%s) - started >= timeout_seconds )); then
            echo "Timed out waiting for zone registration: zone=$expected_zone health=$body" >&2
            return 1
        fi
        sleep 0.2
    done
}

wait_for_file() {
    local name="$1"
    local path="$2"
    local process_pid="$3"
    local timeout_seconds="$4"
    local started

    started="$(date +%s)"
    while true; do
        if [[ -s "$path" ]]; then
            return 0
        fi
        if ! kill -0 "$process_pid" 2>/dev/null; then
            echo "$name exited before writing $path" >&2
            return 1
        fi
        if (( $(date +%s) - started >= timeout_seconds )); then
            echo "Timed out waiting for $name to write $path" >&2
            return 1
        fi
        sleep 0.2
    done
}

show_result() {
    local name="$1"
    local path="$2"

    if [[ -s "$path" ]]; then
        echo "$name result: $path"
        cat "$path"
        return 0
    fi

    echo "$name result file was not written: $path" >&2
    return 1
}

mkdir -p "$artifact_dir"
supervisor_install_traps

orchestrator_game_port="$(allocate_port)"
orchestrator_client_port="$(allocate_port)"
orchestrator_health_port="$(allocate_port)"
zone_port="$(allocate_port)"
gameplay_result_file="$artifact_dir/gameplay-result.json"
coordination_dir="$artifact_dir/multi-client"
observer_result_file="$artifact_dir/multi-client-observer-result.json"
actor_result_file="$artifact_dir/multi-client-actor-result.json"

mkdir -p "$coordination_dir"

printf '%s\n' \
    "run_id=$run_id" \
    "artifact_dir=$artifact_dir" \
    "zone_id=$zone_id" \
    "username=$username" \
    "orchestrator_game_port=$orchestrator_game_port" \
    "orchestrator_client_port=$orchestrator_client_port" \
    "orchestrator_health_port=$orchestrator_health_port" \
    "zone_port=$zone_port" \
    > "$artifact_dir/run.env"

supervisor_start \
    "orchestrator" \
    "$artifact_dir/orchestrator.log" \
    "$project_root" \
    "$script_dir/run_orchestrator.sh" \
    "--default-zone" "$zone_id" \
    "--game-server-port" "$orchestrator_game_port" \
    "--client-port" "$orchestrator_client_port" \
    "--health-port" "$orchestrator_health_port"
orchestrator_pid="$started_pid"

wait_for_url "orchestrator readiness" "http://127.0.0.1:$orchestrator_health_port/readyz" 10

supervisor_start \
    "zone:$zone_id" \
    "$artifact_dir/zone-$zone_id.log" \
    "$project_root" \
    env "ORHYN_GODOT_RUNTIME_DIR=$artifact_dir/runtime-zone-$zone_id" \
    "$script_dir/godot-sandboxed.sh" \
    "--headless" \
    "--path" "./godot" \
    "--scene" "res://projects/game-server/src/main.tscn" \
    "--" \
    "--zone" "$zone_id" \
    "--port" "$zone_port" \
    "--advertise-address" "127.0.0.1" \
    "--orchestrator-url" "ws://127.0.0.1:$orchestrator_game_port/ws"
zone_pid="$started_pid"

wait_for_zone_registration "http://127.0.0.1:$orchestrator_health_port/healthz" "$zone_id" 15

supervisor_start \
    "gameplay-client" \
    "$artifact_dir/gameplay-client.log" \
    "$project_root" \
    timeout "${suite_timeout_seconds}s" \
    env "ORHYN_GODOT_RUNTIME_DIR=$artifact_dir/runtime-gameplay-client" \
    "$script_dir/godot-sandboxed.sh" \
    "--headless" \
    "--path" "./godot" \
    "--scene" "res://projects/e2e/e2e_client.tscn" \
    "--" \
    "--orchestrator-url" "ws://127.0.0.1:$orchestrator_client_port/ws" \
    "--username" "$username" \
    "--zone" "$zone_id" \
    "--suite" "gameplay" \
    "--result-file" "$gameplay_result_file"
client_pid="$started_pid"

exited_pid=
set +e
wait -n -p exited_pid "$orchestrator_pid" "$zone_pid" "$client_pid"
status="$?"
set -e

if [[ "${exited_pid:-}" != "$client_pid" ]]; then
    echo "Infrastructure process exited before E2E client completed: pid=${exited_pid:-unknown} status=$status" >&2
    if (( status == 0 )); then
        status=1
    fi
else
    _supervisor_remove_pid "$client_pid"
fi

if ! show_result "Gameplay" "$gameplay_result_file"; then
    status=1
fi

if (( status != 0 )); then
    trap - EXIT
    supervisor_stop_all
    echo "E2E artifacts: $artifact_dir"
    exit "$status"
fi

supervisor_start \
    "multi-client-observer" \
    "$artifact_dir/multi-client-observer.log" \
    "$project_root" \
    timeout "${suite_timeout_seconds}s" \
    env "ORHYN_GODOT_RUNTIME_DIR=$artifact_dir/runtime-multi-client-observer" \
    "$script_dir/godot-sandboxed.sh" \
    "--headless" \
    "--path" "./godot" \
    "--scene" "res://projects/e2e/e2e_client.tscn" \
    "--" \
    "--orchestrator-url" "ws://127.0.0.1:$orchestrator_client_port/ws" \
    "--username" "e2e_observer" \
    "--zone" "$zone_id" \
    "--suite" "multi_client_observer" \
    "--coordination-dir" "$coordination_dir" \
    "--result-file" "$observer_result_file"
observer_pid="$started_pid"

if ! wait_for_file \
    "multi-client observer" \
    "$coordination_dir/observer-ready.json" \
    "$observer_pid" \
    "$suite_timeout_seconds"; then
    status=1
    trap - EXIT
    supervisor_stop_all
    show_result "Multi-client observer" "$observer_result_file" || true
    echo "E2E artifacts: $artifact_dir"
    exit "$status"
fi

supervisor_start \
    "multi-client-actor" \
    "$artifact_dir/multi-client-actor.log" \
    "$project_root" \
    timeout "${suite_timeout_seconds}s" \
    env "ORHYN_GODOT_RUNTIME_DIR=$artifact_dir/runtime-multi-client-actor" \
    "$script_dir/godot-sandboxed.sh" \
    "--headless" \
    "--path" "./godot" \
    "--scene" "res://projects/e2e/e2e_client.tscn" \
    "--" \
    "--orchestrator-url" "ws://127.0.0.1:$orchestrator_client_port/ws" \
    "--username" "e2e_actor" \
    "--zone" "$zone_id" \
    "--suite" "multi_client_actor" \
    "--coordination-dir" "$coordination_dir" \
    "--result-file" "$actor_result_file"
actor_pid="$started_pid"

set +e
wait "$actor_pid"
actor_status="$?"
set -e
_supervisor_remove_pid "$actor_pid"
if (( actor_status != 0 )); then
    status="$actor_status"
    trap - EXIT
    supervisor_stop_all
    show_result "Multi-client actor" "$actor_result_file" || true
    show_result "Multi-client observer" "$observer_result_file" || true
    echo "E2E artifacts: $artifact_dir"
    exit "$status"
fi

set +e
wait "$observer_pid"
observer_status="$?"
set -e
_supervisor_remove_pid "$observer_pid"
if (( observer_status != 0 )); then
    status="$observer_status"
fi
if ! show_result "Multi-client actor" "$actor_result_file"; then
    status=1
fi
if ! show_result "Multi-client observer" "$observer_result_file"; then
    status=1
fi

trap - EXIT
supervisor_stop_all
echo "E2E artifacts: $artifact_dir"
exit "$status"
