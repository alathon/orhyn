#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
log_root="${ORHYN_LOG_DIR:-$project_root/logs}/e2e-impaired"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
artifact_dir="$log_root/$run_id"
zone_id="mvp"
client_timeout_seconds="${ORHYN_E2E_IMPAIRED_CLIENT_TIMEOUT_SECONDS:-30}"
process_timeout_seconds="${ORHYN_E2E_IMPAIRED_PROCESS_TIMEOUT_SECONDS:-120}"
go_bin="${GO_BIN:-go}"

a_rtt_ms="${ORHYN_E2E_A_RTT_MS:-400}"
a_jitter_ms="${ORHYN_E2E_A_JITTER_MS:-40}"
a_loss_percent="${ORHYN_E2E_A_LOSS_PERCENT:-2}"
a_seed="${ORHYN_E2E_A_SEED:-1001}"
b_rtt_ms="${ORHYN_E2E_B_RTT_MS:-250}"
b_jitter_ms="${ORHYN_E2E_B_JITTER_MS:-20}"
b_loss_percent="${ORHYN_E2E_B_LOSS_PERCENT:-1}"
b_seed="${ORHYN_E2E_B_SEED:-1002}"
c_rtt_ms="${ORHYN_E2E_C_RTT_MS:-20}"
c_jitter_ms="${ORHYN_E2E_C_JITTER_MS:-2}"
c_loss_percent="${ORHYN_E2E_C_LOSS_PERCENT:-0}"
c_seed="${ORHYN_E2E_C_SEED:-1003}"

source "$script_dir/lib/process_supervisor.sh"

usage() {
    cat <<EOF
Usage: $0 [--zone ZONE_ID] [--client-timeout SECONDS] [--process-timeout SECONDS]

Runs only the three-client impaired-network eventual-consistency suite. It does
not run or replace the clean E2E suite. Artifacts are written under
logs/e2e-impaired/.

Profiles are symmetric RTT targets and can be changed with:
  ORHYN_E2E_A_RTT_MS / A_JITTER_MS / A_LOSS_PERCENT / A_SEED
  ORHYN_E2E_B_RTT_MS / B_JITTER_MS / B_LOSS_PERCENT / B_SEED
  ORHYN_E2E_C_RTT_MS / C_JITTER_MS / C_LOSS_PERCENT / C_SEED
EOF
}

while (($# > 0)); do
    case "$1" in
        --zone|--zone-id)
            zone_id="${2:-}"
            shift 2
            ;;
        --client-timeout)
            client_timeout_seconds="${2:-}"
            shift 2
            ;;
        --process-timeout)
            process_timeout_seconds="${2:-}"
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

for value in "$client_timeout_seconds" "$process_timeout_seconds" \
        "$a_rtt_ms" "$a_jitter_ms" "$a_seed" \
        "$b_rtt_ms" "$b_jitter_ms" "$b_seed" \
        "$c_rtt_ms" "$c_jitter_ms" "$c_seed"; do
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "Timeouts, delays, jitter, and seeds must be non-negative integers: $value" >&2
        exit 2
    fi
done
if (( client_timeout_seconds <= 0 || process_timeout_seconds <= 0 )); then
    echo "Timeouts must be positive." >&2
    exit 2
fi

if ! command -v timeout >/dev/null 2>&1; then
    echo "Missing required command: timeout" >&2
    exit 127
fi
if ! command -v "$go_bin" >/dev/null 2>&1; then
    echo "Missing Go executable: $go_bin" >&2
    exit 127
fi

allocated_ports=()

allocate_port() {
    local output_name="$1"
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
        printf -v "$output_name" '%s' "$candidate"
        return 0
    done

    echo "Could not allocate a free port." >&2
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

show_proxy_stats() {
    local name="$1"
    local path="$2"

    if [[ -s "$path" ]]; then
        echo "$name proxy stats: $path"
        cat "$path"
    fi
}

start_proxy() {
    local name="$1"
    local listen_port="$2"
    local rtt_ms="$3"
    local jitter_ms="$4"
    local loss_percent="$5"
    local seed="$6"
    local pid_output_name="$7"
    local one_way_ms=$((rtt_ms / 2))

    supervisor_start \
        "proxy-$name" \
        "$artifact_dir/proxy-$name.log" \
        "$project_root" \
        "$proxy_bin" \
        "--listen-address" "127.0.0.1" \
        "--listen-port" "$listen_port" \
        "--target-address" "127.0.0.1" \
        "--target-port" "$zone_port" \
        "--up-delay" "${one_way_ms}ms" \
        "--down-delay" "${one_way_ms}ms" \
        "--up-jitter" "${jitter_ms}ms" \
        "--down-jitter" "${jitter_ms}ms" \
        "--up-loss-percent" "$loss_percent" \
        "--down-loss-percent" "$loss_percent" \
        "--seed" "$seed" \
        "--ready-file" "$artifact_dir/proxy-$name-ready.json" \
        "--stats-file" "$artifact_dir/proxy-$name-stats.json"
    printf -v "$pid_output_name" '%s' "$started_pid"
}

start_client() {
    local name="$1"
    local username="$2"
    local suite="$3"
    local role="$4"
    local proxy_port="$5"
    local result_file="$6"
    local pid_output_name="$7"
    local client_args=(
        "--orchestrator-url" "ws://127.0.0.1:$orchestrator_client_port/ws"
        "--username" "$username"
        "--zone" "$zone_id"
        "--suite" "$suite"
        "--coordination-dir" "$coordination_dir"
        "--timeout" "$client_timeout_seconds"
        "--zone-connect-address" "127.0.0.1"
        "--zone-connect-port" "$proxy_port"
        "--result-file" "$result_file"
    )
    if [[ -n "$role" ]]; then
        client_args+=("--client-role" "$role")
    fi

    supervisor_start \
        "$name" \
        "$artifact_dir/$name.log" \
        "$project_root" \
        timeout "${process_timeout_seconds}s" \
        env "ORHYN_GODOT_RUNTIME_DIR=$artifact_dir/runtime-$name" \
        "$script_dir/godot-sandboxed.sh" \
        "--headless" \
        "--path" "./godot" \
        "--scene" "res://projects/e2e/e2e_client.tscn" \
        "--" \
        "${client_args[@]}"
    printf -v "$pid_output_name" '%s' "$started_pid"
}

stop_and_report_failure() {
    local status="$1"
    trap - EXIT
    supervisor_stop_all
    show_result "Impaired observer" "$observer_result_file" || true
    show_result "Impaired actor" "$actor_result_file" || true
    show_result "Impaired joiner" "$joiner_result_file" || true
    show_proxy_stats "Client A" "$artifact_dir/proxy-a-stats.json"
    show_proxy_stats "Client B" "$artifact_dir/proxy-b-stats.json"
    show_proxy_stats "Client C" "$artifact_dir/proxy-c-stats.json"
    echo "Impaired E2E artifacts: $artifact_dir"
    exit "$status"
}

mkdir -p "$artifact_dir"
supervisor_install_traps

allocate_port orchestrator_game_port
allocate_port orchestrator_client_port
allocate_port orchestrator_health_port
allocate_port zone_port
allocate_port proxy_a_port
allocate_port proxy_b_port
allocate_port proxy_c_port

coordination_dir="$artifact_dir/coordination"
observer_result_file="$artifact_dir/impaired-observer-result.json"
actor_result_file="$artifact_dir/impaired-actor-result.json"
joiner_result_file="$artifact_dir/impaired-joiner-result.json"
proxy_bin="$artifact_dir/udp-impairment-proxy"
mkdir -p "$coordination_dir"

printf '%s\n' \
    "run_id=$run_id" \
    "artifact_dir=$artifact_dir" \
    "zone_id=$zone_id" \
    "orchestrator_game_port=$orchestrator_game_port" \
    "orchestrator_client_port=$orchestrator_client_port" \
    "orchestrator_health_port=$orchestrator_health_port" \
    "zone_port=$zone_port" \
    "client_timeout_seconds=$client_timeout_seconds" \
    "process_timeout_seconds=$process_timeout_seconds" \
    "client_a_profile=rtt:${a_rtt_ms}ms,jitter:${a_jitter_ms}ms,loss:${a_loss_percent}%,seed:$a_seed,port:$proxy_a_port" \
    "client_b_profile=rtt:${b_rtt_ms}ms,jitter:${b_jitter_ms}ms,loss:${b_loss_percent}%,seed:$b_seed,port:$proxy_b_port" \
    "client_c_profile=rtt:${c_rtt_ms}ms,jitter:${c_jitter_ms}ms,loss:${c_loss_percent}%,seed:$c_seed,port:$proxy_c_port" \
    > "$artifact_dir/run.env"

env GOCACHE="$artifact_dir/go-cache" "$go_bin" \
    -C "$project_root/test/network/udp-impairment-proxy" build \
    -o "$proxy_bin" \
    .

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

start_proxy "a" "$proxy_a_port" "$a_rtt_ms" "$a_jitter_ms" "$a_loss_percent" "$a_seed" proxy_a_pid
start_proxy "b" "$proxy_b_port" "$b_rtt_ms" "$b_jitter_ms" "$b_loss_percent" "$b_seed" proxy_b_pid
start_proxy "c" "$proxy_c_port" "$c_rtt_ms" "$c_jitter_ms" "$c_loss_percent" "$c_seed" proxy_c_pid

for proxy_name in a b c; do
    proxy_pid_variable="proxy_${proxy_name}_pid"
    if ! wait_for_file \
        "client $proxy_name proxy" \
        "$artifact_dir/proxy-$proxy_name-ready.json" \
        "${!proxy_pid_variable}" \
        10; then
        stop_and_report_failure 1
    fi
done

start_client \
    "impaired-observer" \
    "e2e_impaired_observer" \
    "impaired_network_peer" \
    "observer" \
    "$proxy_a_port" \
    "$observer_result_file" \
    observer_pid

if ! wait_for_file \
    "impaired observer" \
    "$coordination_dir/impaired-observer-ready.json" \
    "$observer_pid" \
    "$process_timeout_seconds"; then
    stop_and_report_failure 1
fi

start_client \
    "impaired-actor" \
    "e2e_impaired_actor" \
    "impaired_network_actor" \
    "" \
    "$proxy_b_port" \
    "$actor_result_file" \
    actor_pid

if ! wait_for_file \
    "first two impaired clients" \
    "$coordination_dir/impaired-first-two-verified.json" \
    "$actor_pid" \
    "$process_timeout_seconds"; then
    stop_and_report_failure 1
fi

start_client \
    "impaired-joiner" \
    "e2e_impaired_joiner" \
    "impaired_network_peer" \
    "joiner" \
    "$proxy_c_port" \
    "$joiner_result_file" \
    joiner_pid

set +e
wait "$actor_pid"
actor_status="$?"
set -e
_supervisor_remove_pid "$actor_pid"
if (( actor_status != 0 )); then
    stop_and_report_failure "$actor_status"
fi

set +e
wait "$observer_pid"
observer_status="$?"
set -e
_supervisor_remove_pid "$observer_pid"
if (( observer_status != 0 )); then
    stop_and_report_failure "$observer_status"
fi

set +e
wait "$joiner_pid"
joiner_status="$?"
set -e
_supervisor_remove_pid "$joiner_pid"
if (( joiner_status != 0 )); then
    stop_and_report_failure "$joiner_status"
fi

result_status=0
show_result "Impaired observer" "$observer_result_file" || result_status=1
show_result "Impaired actor" "$actor_result_file" || result_status=1
show_result "Impaired joiner" "$joiner_result_file" || result_status=1

trap - EXIT
supervisor_stop_all
show_proxy_stats "Client A" "$artifact_dir/proxy-a-stats.json"
show_proxy_stats "Client B" "$artifact_dir/proxy-b-stats.json"
show_proxy_stats "Client C" "$artifact_dir/proxy-c-stats.json"
echo "Impaired E2E artifacts: $artifact_dir"
exit "$result_status"
