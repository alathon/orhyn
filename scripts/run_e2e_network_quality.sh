#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
log_root="${ORHYN_LOG_DIR:-$project_root/logs}/e2e-network-quality"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
artifact_dir="$log_root/$run_id"
coordination_dir="$artifact_dir/coordination"
zone_id="mvp"
movement_duration_seconds="${ORHYN_E2E_NETWORK_QUALITY_MOVEMENT_SECONDS:-20}"
metrics_drain_seconds="${ORHYN_E2E_NETWORK_QUALITY_DRAIN_SECONDS:-2}"
client_timeout_seconds="${ORHYN_E2E_NETWORK_QUALITY_CLIENT_TIMEOUT_SECONDS:-45}"
process_timeout_seconds="${ORHYN_E2E_NETWORK_QUALITY_PROCESS_TIMEOUT_SECONDS:-120}"
headless="${HEADLESS:-1}"
go_bin="${GO_BIN:-go}"

low_rtt_ms="${ORHYN_E2E_NETWORK_QUALITY_LOW_RTT_MS:-20}"
low_jitter_ms="${ORHYN_E2E_NETWORK_QUALITY_LOW_JITTER_MS:-2}"
low_loss_percent="${ORHYN_E2E_NETWORK_QUALITY_LOW_LOSS_PERCENT:-0}"
low_seed="${ORHYN_E2E_NETWORK_QUALITY_LOW_SEED:-1003}"
high_rtt_ms="${ORHYN_E2E_NETWORK_QUALITY_HIGH_RTT_MS:-400}"
high_jitter_ms="${ORHYN_E2E_NETWORK_QUALITY_HIGH_JITTER_MS:-40}"
high_loss_percent="${ORHYN_E2E_NETWORK_QUALITY_HIGH_LOSS_PERCENT:-2}"
high_seed="${ORHYN_E2E_NETWORK_QUALITY_HIGH_SEED:-1001}"
max_low_average_playout_delay="${ORHYN_E2E_NETWORK_QUALITY_MAX_LOW_AVERAGE_PLAYOUT_DELAY:-0.075}"
max_high_average_playout_delay="${ORHYN_E2E_NETWORK_QUALITY_MAX_HIGH_AVERAGE_PLAYOUT_DELAY:-0.30}"
max_high_stall_ratio="${ORHYN_E2E_NETWORK_QUALITY_MAX_HIGH_STALL_RATIO:-0.05}"
max_high_frame_distance="${ORHYN_E2E_NETWORK_QUALITY_MAX_HIGH_FRAME_DISTANCE:-0.25}"
max_hard_snaps="${ORHYN_E2E_NETWORK_QUALITY_MAX_HARD_SNAPS:-0}"

source "$script_dir/lib/process_supervisor.sh"

usage() {
    cat <<EOF
Usage: $0 [--zone ZONE_ID] [--movement-duration SECONDS] [--process-timeout SECONDS]

Runs a focused two-client remote-motion quality workload. One client uses a
low-latency profile and one uses a high-latency profile. Each moves while the
other records the real rendered remote entity, giving both observation
directions without repeating gameplay correctness assertions.

Set HEADLESS=0 to launch the two Godot clients in regular windowed mode. The
orchestrator and zone server remain headless. HEADLESS defaults to 1.

Profiles can be changed with:
  ORHYN_E2E_NETWORK_QUALITY_LOW_RTT_MS
  ORHYN_E2E_NETWORK_QUALITY_LOW_JITTER_MS
  ORHYN_E2E_NETWORK_QUALITY_LOW_LOSS_PERCENT
  ORHYN_E2E_NETWORK_QUALITY_LOW_SEED
  ORHYN_E2E_NETWORK_QUALITY_HIGH_RTT_MS
  ORHYN_E2E_NETWORK_QUALITY_HIGH_JITTER_MS
  ORHYN_E2E_NETWORK_QUALITY_HIGH_LOSS_PERCENT
  ORHYN_E2E_NETWORK_QUALITY_HIGH_SEED

Visual-quality budgets can be changed with:
  ORHYN_E2E_NETWORK_QUALITY_MAX_LOW_AVERAGE_PLAYOUT_DELAY
  ORHYN_E2E_NETWORK_QUALITY_MAX_HIGH_AVERAGE_PLAYOUT_DELAY
  ORHYN_E2E_NETWORK_QUALITY_MAX_HIGH_STALL_RATIO
  ORHYN_E2E_NETWORK_QUALITY_MAX_HIGH_FRAME_DISTANCE
  ORHYN_E2E_NETWORK_QUALITY_MAX_HARD_SNAPS
EOF
}

while (($# > 0)); do
    case "$1" in
        --zone|--zone-id)
            zone_id="${2:-}"
            shift 2
            ;;
        --movement-duration)
            movement_duration_seconds="${2:-}"
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
case "$headless" in
    0)
        client_display_args=("--windowed")
        ;;
    1)
        client_display_args=("--headless")
        ;;
    *)
        echo "HEADLESS must be 0 or 1: $headless" >&2
        exit 2
        ;;
esac
for value in "$movement_duration_seconds" "$metrics_drain_seconds" \
        "$client_timeout_seconds" "$process_timeout_seconds" \
        "$low_rtt_ms" "$low_jitter_ms" "$low_seed" \
        "$high_rtt_ms" "$high_jitter_ms" "$high_seed" "$max_hard_snaps"; do
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "Durations, delays, jitter, and seeds must be non-negative integers: $value" >&2
        exit 2
    fi
done
for value in "$low_loss_percent" "$high_loss_percent" \
        "$max_low_average_playout_delay" "$max_high_average_playout_delay" \
        "$max_high_stall_ratio" \
        "$max_high_frame_distance"; do
    if ! [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "Loss percentages and quality budgets must be non-negative numbers: $value" >&2
        exit 2
    fi
done
if (( movement_duration_seconds <= 0 || client_timeout_seconds <= 0 || process_timeout_seconds <= 0 )); then
    echo "Movement duration and timeouts must be positive." >&2
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
        sed -n '1,20p' "$path"
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
        sed -n '1,20p' "$path"
    fi
}

extract_metric() {
    local path="$1"
    local key="$2"
    local contents
    local pattern

    if [[ ! -s "$path" ]]; then
        printf 'n/a'
        return 0
    fi
    contents="$(tr -d '\n' < "$path")"
    pattern="\"${key}\":(-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?)"
    if [[ "$contents" =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    printf 'n/a'
}

format_decimal_metric() {
    local value

    value="$(extract_metric "$1" "$2")"
    if [[ "$value" == "n/a" ]]; then
        printf 'n/a'
        return 0
    fi
    LC_ALL=C printf '%.3f' "$value"
}

format_ratio_metric() {
    local value

    value="$(extract_metric "$1" "$2")"
    if [[ "$value" == "n/a" ]]; then
        printf 'n/a'
        return 0
    fi
    awk -v ratio="$value" 'BEGIN { printf "%.1f%%", ratio * 100.0 }'
}

format_milliseconds_metric() {
    local value

    value="$(extract_metric "$1" "$2")"
    if [[ "$value" == "n/a" ]]; then
        printf 'n/a'
        return 0
    fi
    awk -v seconds="$value" 'BEGIN { printf "%.1f", seconds * 1000.0 }'
}

metric_is_greater() {
    local greater_value
    local lesser_value

    greater_value="$(extract_metric "$1" "$3")"
    lesser_value="$(extract_metric "$2" "$3")"
    if [[ "$greater_value" == "n/a" || "$lesser_value" == "n/a" ]]; then
        return 1
    fi
    awk -v greater="$greater_value" -v lesser="$lesser_value" \
        'BEGIN { exit !(greater > lesser) }'
}

metric_is_less_than_or_equal() {
    local observed_value

    observed_value="$(extract_metric "$1" "$2")"
    if [[ "$observed_value" == "n/a" ]]; then
        return 1
    fi
    awk -v observed="$observed_value" -v maximum="$3" \
        'BEGIN { exit !(observed <= maximum) }'
}

assert_remote_view_quality() {
    local high_observer_result="$artifact_dir/client-high-result.json"
    local low_observer_result="$artifact_dir/client-low-result.json"

    if ! metric_is_greater \
            "$high_observer_result" "$low_observer_result" \
            remote_average_target_playout_delay; then
        echo "Expected adaptive playout to assign more delay to the impaired observer." >&2
        return 1
    fi
    if ! metric_is_less_than_or_equal \
            "$low_observer_result" remote_average_playout_delay \
            "$max_low_average_playout_delay"; then
        echo "Low-latency observer exceeded the average playout-delay budget." >&2
        return 1
    fi
    if ! metric_is_less_than_or_equal \
            "$high_observer_result" remote_average_playout_delay \
            "$max_high_average_playout_delay"; then
        echo "High-latency observer exceeded the average playout-delay budget." >&2
        return 1
    fi
    if ! metric_is_less_than_or_equal \
            "$high_observer_result" remote_stall_ratio "$max_high_stall_ratio"; then
        echo "High-latency observer exceeded the stalled-motion budget." >&2
        return 1
    fi
    if ! metric_is_less_than_or_equal \
            "$high_observer_result" remote_max_frame_distance "$max_high_frame_distance" \
            || ! metric_is_less_than_or_equal \
            "$low_observer_result" remote_max_frame_distance "$max_high_frame_distance"; then
        echo "A remote observer exceeded the worst-frame-step budget." >&2
        return 1
    fi
    if ! metric_is_less_than_or_equal \
            "$high_observer_result" remote_hard_snap_count "$max_hard_snaps" \
            || ! metric_is_less_than_or_equal \
            "$low_observer_result" remote_hard_snap_count "$max_hard_snaps"; then
        echo "A remote observer exceeded the hard-snap budget." >&2
        return 1
    fi
    if ! metric_is_less_than_or_equal \
            "$high_observer_result" dropped_metric_value_count 0 \
            || ! metric_is_less_than_or_equal \
            "$low_observer_result" dropped_metric_value_count 0; then
        echo "A remote observer exhausted its preallocated metric sample storage." >&2
        return 1
    fi
}

print_quality_summary() {
    local high_observer_result="$artifact_dir/client-high-result.json"
    local low_observer_result="$artifact_dir/client-low-result.json"
    local path
    local label

    printf '\nRemote-motion quality summary\n'
    printf 'low:  %s ms RTT, %s ms jitter, %s%% loss\n' \
        "$low_rtt_ms" "$low_jitter_ms" "$low_loss_percent"
    printf 'high: %s ms RTT, %s ms jitter, %s%% loss\n' \
        "$high_rtt_ms" "$high_jitter_ms" "$high_loss_percent"
    printf '%-32s %9s %9s %8s %9s %7s %7s %13s %10s\n' \
        'view' 'delay-ms' 'target-ms' 'extra%' 'p95-corr' 'stalls' 'snaps' 'p95-speed-err' 'max-step'
    for entry in \
            "high observes low|$high_observer_result" \
            "low observes high|$low_observer_result"; do
        label="${entry%%|*}"
        path="${entry#*|}"
        printf '%-32s %9s %9s %8s %9s %7s %7s %13s %10s\n' \
            "$label" \
            "$(format_milliseconds_metric "$path" remote_average_playout_delay)" \
            "$(format_milliseconds_metric "$path" remote_average_target_playout_delay)" \
            "$(format_ratio_metric "$path" remote_extrapolated_ratio)" \
            "$(format_decimal_metric "$path" remote_p95_correction_distance)" \
            "$(extract_metric "$path" remote_stall_episode_count)" \
            "$(extract_metric "$path" remote_hard_snap_count)" \
            "$(format_decimal_metric "$path" remote_p95_speed_error)" \
            "$(format_decimal_metric "$path" remote_max_frame_distance)"
    done
    echo "delay/target are adaptive playout milliseconds; extra is bounded extrapolation time."
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
        "quality-proxy-$name" \
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
    local role="$1"
    local proxy_port="$2"
    local rtt_ms="$3"
    local jitter_ms="$4"
    local loss_percent="$5"
    local result_file="$artifact_dir/client-$role-result.json"
    local profile="${role}:rtt:${rtt_ms}ms,jitter:${jitter_ms}ms,loss:${loss_percent}%"
    local pid_output_name="$6"

    supervisor_start \
        "network-quality-$role" \
        "$artifact_dir/client-$role.log" \
        "$project_root" \
        timeout "${process_timeout_seconds}s" \
        env "ORHYN_GODOT_RUNTIME_DIR=$artifact_dir/runtime-$role" \
        "$script_dir/godot-sandboxed.sh" \
        "${client_display_args[@]}" \
        "--path" "./godot" \
        "--scene" "res://projects/e2e/e2e_client.tscn" \
        "--" \
        "--orchestrator-url" "ws://127.0.0.1:$orchestrator_client_port/ws" \
        "--username" "e2e_network_quality_$role" \
        "--zone" "$zone_id" \
        "--suite" "network_quality" \
        "--client-role" "$role" \
        "--network-profile" "$profile" \
        "--coordination-dir" "$coordination_dir" \
        "--timeout" "$client_timeout_seconds" \
        "--zone-connect-address" "127.0.0.1" \
        "--zone-connect-port" "$proxy_port" \
        "--movement-duration" "$movement_duration_seconds" \
        "--metrics-drain" "$metrics_drain_seconds" \
        "--min-remote-motion-samples" "$minimum_remote_motion_samples" \
        "--result-file" "$result_file"
    printf -v "$pid_output_name" '%s' "$started_pid"
}

stop_and_report_failure() {
    local status="$1"
    trap - EXIT
    supervisor_stop_all
    show_result "Low-latency client" "$artifact_dir/client-low-result.json" || true
    show_result "High-latency client" "$artifact_dir/client-high-result.json" || true
    print_quality_summary
    show_proxy_stats "Low-latency client" "$artifact_dir/proxy-low-stats.json"
    show_proxy_stats "High-latency client" "$artifact_dir/proxy-high-stats.json"
    echo "Network-quality E2E artifacts: $artifact_dir"
    exit "$status"
}

mkdir -p "$coordination_dir"
supervisor_install_traps

allocate_port orchestrator_game_port
allocate_port orchestrator_client_port
allocate_port orchestrator_health_port
allocate_port zone_port
allocate_port proxy_low_port
allocate_port proxy_high_port

minimum_remote_motion_samples=$((movement_duration_seconds * 5))
proxy_bin="$artifact_dir/udp-impairment-proxy"

printf '%s\n' \
    "run_id=$run_id" \
    "artifact_dir=$artifact_dir" \
    "zone_id=$zone_id" \
    "movement_duration_seconds=$movement_duration_seconds" \
    "metrics_drain_seconds=$metrics_drain_seconds" \
    "headless=$headless" \
    "minimum_remote_motion_samples=$minimum_remote_motion_samples" \
    "max_low_average_playout_delay=$max_low_average_playout_delay" \
    "max_high_average_playout_delay=$max_high_average_playout_delay" \
    "max_high_stall_ratio=$max_high_stall_ratio" \
    "max_high_frame_distance=$max_high_frame_distance" \
    "max_hard_snaps=$max_hard_snaps" \
    "low_profile=rtt:${low_rtt_ms}ms,jitter:${low_jitter_ms}ms,loss:${low_loss_percent}%,seed:$low_seed,port:$proxy_low_port" \
    "high_profile=rtt:${high_rtt_ms}ms,jitter:${high_jitter_ms}ms,loss:${high_loss_percent}%,seed:$high_seed,port:$proxy_high_port" \
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

wait_for_zone_registration "http://127.0.0.1:$orchestrator_health_port/healthz" "$zone_id" 15

start_proxy \
    "low" "$proxy_low_port" "$low_rtt_ms" "$low_jitter_ms" \
    "$low_loss_percent" "$low_seed" proxy_low_pid
start_proxy \
    "high" "$proxy_high_port" "$high_rtt_ms" "$high_jitter_ms" \
    "$high_loss_percent" "$high_seed" proxy_high_pid

if ! wait_for_file \
        "low-latency proxy" "$artifact_dir/proxy-low-ready.json" \
        "$proxy_low_pid" 10; then
    stop_and_report_failure 1
fi
if ! wait_for_file \
        "high-latency proxy" "$artifact_dir/proxy-high-ready.json" \
        "$proxy_high_pid" 10; then
    stop_and_report_failure 1
fi

start_client \
    "low" "$proxy_low_port" "$low_rtt_ms" "$low_jitter_ms" \
    "$low_loss_percent" low_client_pid
start_client \
    "high" "$proxy_high_port" "$high_rtt_ms" "$high_jitter_ms" \
    "$high_loss_percent" high_client_pid

set +e
wait "$low_client_pid"
low_status="$?"
wait "$high_client_pid"
high_status="$?"
set -e
_supervisor_remove_pid "$low_client_pid"
_supervisor_remove_pid "$high_client_pid"

result_status=0
if ! show_result "Low-latency client" "$artifact_dir/client-low-result.json"; then
    result_status=1
fi
if ! show_result "High-latency client" "$artifact_dir/client-high-result.json"; then
    result_status=1
fi
if (( low_status != 0 || high_status != 0 || result_status != 0 )); then
    stop_and_report_failure 1
fi

print_quality_summary
if ! assert_remote_view_quality; then
    stop_and_report_failure 1
fi

trap - EXIT
supervisor_stop_all
show_proxy_stats "Low-latency client" "$artifact_dir/proxy-low-stats.json"
show_proxy_stats "High-latency client" "$artifact_dir/proxy-high-stats.json"
echo "Network-quality E2E artifacts: $artifact_dir"
