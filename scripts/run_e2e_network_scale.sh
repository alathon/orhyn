#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
log_root="${ORHYN_LOG_DIR:-$project_root/logs}/e2e-network-scale"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
artifact_dir="$log_root/$run_id"
coordination_dir="$artifact_dir/coordination"
zone_id="mvp"
client_count="${ORHYN_E2E_NETWORK_SCALE_CLIENTS:-50}"
movement_duration_seconds="${ORHYN_E2E_NETWORK_SCALE_MOVEMENT_SECONDS:-30}"
metrics_drain_seconds="${ORHYN_E2E_NETWORK_SCALE_DRAIN_SECONDS:-2}"
client_timeout_seconds="${ORHYN_E2E_NETWORK_SCALE_CLIENT_TIMEOUT_SECONDS:-120}"
process_timeout_seconds="${ORHYN_E2E_NETWORK_SCALE_PROCESS_TIMEOUT_SECONDS:-240}"
startup_batch_size="${ORHYN_E2E_NETWORK_SCALE_STARTUP_BATCH_SIZE:-5}"
orchestrator_transfer_ttl="${ORHYN_E2E_NETWORK_SCALE_TRANSFER_TTL:-180s}"
minimum_rtt_ms="${ORHYN_E2E_NETWORK_SCALE_MIN_RTT_MS:-20}"
maximum_rtt_ms="${ORHYN_E2E_NETWORK_SCALE_MAX_RTT_MS:-300}"
loss_percent="${ORHYN_E2E_NETWORK_SCALE_LOSS_PERCENT:-0}"
base_seed="${ORHYN_E2E_NETWORK_SCALE_SEED:-7001}"
headless="${HEADLESS:-1}"
go_bin="${GO_BIN:-go}"

source "$script_dir/lib/process_supervisor.sh"

usage() {
	cat <<EOF
Usage: $0 [--clients COUNT] [--zone ZONE_ID] [--movement-duration SECONDS]

Runs a many-client remote-presentation measurement workload. Every client gets
its own seeded UDP proxy, with RTTs distributed from 20 ms through 300 ms by
default. All clients move in deterministic random directions concurrently for
30 seconds. Clients 0 and COUNT-1 aggregate the normal remote visual-quality
metrics across every other player.

Set HEADLESS=0 to show only client 0 (low delay) and client COUNT-1 (300 ms by
default). Every other client remains headless. HEADLESS defaults to 1.

For a controlled two-client baseline with the same concurrent workload and
profile endpoints, run with --clients 2 and compare the normalized summary.

Environment overrides:
  ORHYN_E2E_NETWORK_SCALE_CLIENTS
  ORHYN_E2E_NETWORK_SCALE_MOVEMENT_SECONDS
  ORHYN_E2E_NETWORK_SCALE_DRAIN_SECONDS
  ORHYN_E2E_NETWORK_SCALE_MIN_RTT_MS
  ORHYN_E2E_NETWORK_SCALE_MAX_RTT_MS
  ORHYN_E2E_NETWORK_SCALE_LOSS_PERCENT
  ORHYN_E2E_NETWORK_SCALE_SEED
  ORHYN_E2E_NETWORK_SCALE_METRIC_SAMPLE_CAPACITY
  ORHYN_E2E_NETWORK_SCALE_CLIENT_TIMEOUT_SECONDS
  ORHYN_E2E_NETWORK_SCALE_PROCESS_TIMEOUT_SECONDS
  ORHYN_E2E_NETWORK_SCALE_STARTUP_BATCH_SIZE
  ORHYN_E2E_NETWORK_SCALE_TRANSFER_TTL
EOF
}

while (($# > 0)); do
	case "$1" in
		--clients)
			client_count="${2:-}"
			shift 2
			;;
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

for value in "$client_count" "$movement_duration_seconds" "$metrics_drain_seconds" \
		"$client_timeout_seconds" "$process_timeout_seconds" "$minimum_rtt_ms" \
		"$maximum_rtt_ms" "$base_seed" "$startup_batch_size"; do
	if ! [[ "$value" =~ ^[0-9]+$ ]]; then
		echo "Counts, durations, delays, and seeds must be non-negative integers: $value" >&2
		exit 2
	fi
done
if ! [[ "$loss_percent" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
	echo "Loss percentage must be a non-negative number: $loss_percent" >&2
	exit 2
fi
if ! awk -v loss="$loss_percent" 'BEGIN { exit !(loss >= 0.0 && loss <= 100.0) }'; then
	echo "Loss percentage must be between 0 and 100: $loss_percent" >&2
	exit 2
fi
if (( client_count < 2 || movement_duration_seconds <= 0 || client_timeout_seconds <= 0 \
		|| process_timeout_seconds <= 0 || minimum_rtt_ms > maximum_rtt_ms )); then
	echo "Require at least two clients, positive durations/timeouts, and min RTT <= max RTT." >&2
	exit 2
fi
if (( startup_batch_size <= 0 )); then
	echo "Startup batch size must be positive: $startup_batch_size" >&2
	exit 2
fi
case "$headless" in
	0|1)
		;;
	*)
		echo "HEADLESS must be 0 or 1: $headless" >&2
		exit 2
		;;
esac
if [[ -z "$zone_id" ]]; then
	echo "Zone id cannot be empty." >&2
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

minimum_remote_motion_samples=$(( (client_count - 1) * movement_duration_seconds * 5 ))
default_metric_sample_capacity=$(( (client_count - 1) * (movement_duration_seconds + metrics_drain_seconds + 5) * 240 ))
metric_sample_capacity="${ORHYN_E2E_NETWORK_SCALE_METRIC_SAMPLE_CAPACITY:-$default_metric_sample_capacity}"
if ! [[ "$metric_sample_capacity" =~ ^[0-9]+$ ]] || (( metric_sample_capacity <= 0 )); then
	echo "Metric sample capacity must be a positive integer: $metric_sample_capacity" >&2
	exit 2
fi

allocated_ports=()
proxy_ports=()
proxy_pids=()
client_pids=()
client_rtts=()
client_jitters=()

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

client_phase_file() {
	local index="$1"
	local phase="$2"
	printf '%s/network-scale-client-%03d-%s.json' "$coordination_dir" "$index" "$phase"
}

write_barrier() {
	local file_name="$1"
	local temporary_path="$coordination_dir/$file_name.tmp"
	printf '{"ok":true}\n' >"$temporary_path"
	mv "$temporary_path" "$coordination_dir/$file_name"
}

wait_for_all_proxy_readiness() {
	local timeout_seconds="$1"
	local started
	local index
	local missing
	local ready_file

	started="$(date +%s)"
	while true; do
		missing=0
		for ((index = 0; index < client_count; index++)); do
			ready_file="$artifact_dir/proxy-$index-ready.json"
			if [[ -s "$ready_file" ]]; then
				continue
			fi
			missing=$((missing + 1))
			if ! kill -0 "${proxy_pids[$index]}" 2>/dev/null; then
				echo "Proxy $index exited before becoming ready." >&2
				return 1
			fi
		done
		if (( missing == 0 )); then
			return 0
		fi
		if (( $(date +%s) - started >= timeout_seconds )); then
			echo "Timed out waiting for $missing network-scale proxies." >&2
			return 1
		fi
		sleep 0.2
	done
}

wait_for_all_client_phase() {
	local phase="$1"
	local timeout_seconds="$2"
	local started
	local index
	local missing
	local path

	started="$(date +%s)"
	while true; do
		missing=0
		for ((index = 0; index < client_count; index++)); do
			path="$(client_phase_file "$index" "$phase")"
			if [[ -s "$path" ]]; then
				continue
			fi
			missing=$((missing + 1))
			if ! kill -0 "${client_pids[$index]}" 2>/dev/null; then
				echo "Client $index exited before phase '$phase'." >&2
				return 1
			fi
		done
		if (( missing == 0 )); then
			return 0
		fi
		if (( $(date +%s) - started >= timeout_seconds )); then
			echo "Timed out waiting for $missing clients at phase '$phase'." >&2
			return 1
		fi
		sleep 0.2
	done
}

wait_for_client_range_phase() {
	local phase="$1"
	local first_index="$2"
	local last_index="$3"
	local timeout_seconds="$4"
	local started
	local index
	local missing
	local path

	started="$(date +%s)"
	while true; do
		missing=0
		for ((index = first_index; index <= last_index; index++)); do
			path="$(client_phase_file "$index" "$phase")"
			if [[ -s "$path" ]]; then
				continue
			fi
			missing=$((missing + 1))
			if ! kill -0 "${client_pids[$index]}" 2>/dev/null; then
				echo "Client $index exited before phase '$phase'." >&2
				return 1
			fi
		done
		if (( missing == 0 )); then
			return 0
		fi
		if (( $(date +%s) - started >= timeout_seconds )); then
			echo "Timed out waiting for clients $first_index-$last_index at phase '$phase'." >&2
			return 1
		fi
		sleep 0.2
	done
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
	contents="$(tr -d '\n' <"$path")"
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

print_scale_summary() {
	local index
	local label
	local result_file

	printf '\nNetwork-scale remote-motion summary\n'
	printf 'clients=%s movement=%ss RTT=%s-%sms loss=%s%%\n' \
		"$client_count" "$movement_duration_seconds" "$minimum_rtt_ms" "$maximum_rtt_ms" "$loss_percent"
	printf '%-28s %7s %9s %9s %8s %8s %9s %7s %13s %10s\n' \
		'observer' 'remotes' 'delay-ms' 'target-ms' 'extra%' 'stall%' 'disc/min' 'snaps' 'p95-speed-err' 'max-step'
	for index in 0 $((client_count - 1)); do
		result_file="$artifact_dir/client-$index-result.json"
		if (( index == 0 )); then
			label="low RTT ${client_rtts[$index]}ms"
		else
			label="high RTT ${client_rtts[$index]}ms"
		fi
		printf '%-28s %7s %9s %9s %8s %8s %9s %7s %13s %10s\n' \
			"$label" \
			"$(extract_metric "$result_file" remote_entity_count)" \
			"$(format_milliseconds_metric "$result_file" remote_average_playout_delay)" \
			"$(format_milliseconds_metric "$result_file" remote_average_target_playout_delay)" \
			"$(format_ratio_metric "$result_file" remote_extrapolated_ratio)" \
			"$(format_ratio_metric "$result_file" remote_stall_ratio)" \
			"$(format_decimal_metric "$result_file" remote_motion_discontinuities_per_minute)" \
			"$(extract_metric "$result_file" remote_hard_snap_count)" \
			"$(format_decimal_metric "$result_file" remote_p95_speed_error)" \
			"$(format_decimal_metric "$result_file" remote_max_frame_distance)"
	done
	echo "Each row aggregates every remote rendered by that observer; artifacts retain full metrics."
}

report_failure() {
	local status="$1"
	local index
	local shown=0
	local omitted=0
	trap - EXIT
	supervisor_stop_all
	for ((index = 0; index < client_count; index++)); do
		if [[ -s "$artifact_dir/client-$index-result.json" ]]; then
			if ! rg -q '"ok":true' "$artifact_dir/client-$index-result.json"; then
				if (( shown < 5 )); then
					echo "Client $index result:"
					sed -n '1,5p' "$artifact_dir/client-$index-result.json"
					shown=$((shown + 1))
				else
					omitted=$((omitted + 1))
				fi
			fi
		elif [[ -s "$artifact_dir/client-$index.log" ]]; then
			if (( shown < 5 )); then
				echo "Client $index did not write a result; log tail:"
				tail -n 20 "$artifact_dir/client-$index.log"
				shown=$((shown + 1))
			else
				omitted=$((omitted + 1))
			fi
		fi
	done
	if (( omitted > 0 )); then
		echo "Omitted $omitted additional failed/missing client log tails; all logs are in the artifacts."
	fi
	for server_log in "$artifact_dir/orchestrator.log" "$artifact_dir/zone-$zone_id.log"; do
		if [[ -s "$server_log" ]]; then
			echo "Server log tail: $server_log"
			tail -n 20 "$server_log"
		fi
	done
	print_scale_summary
	echo "Network-scale E2E artifacts: $artifact_dir"
	exit "$status"
}

mkdir -p "$coordination_dir"
supervisor_install_traps

allocate_port orchestrator_game_port
allocate_port orchestrator_client_port
allocate_port orchestrator_health_port
allocate_port zone_port
for ((index = 0; index < client_count; index++)); do
	allocate_port proxy_port
	proxy_ports+=("$proxy_port")
done

proxy_bin="$artifact_dir/udp-impairment-proxy"
env GOCACHE="$artifact_dir/go-cache" "$go_bin" \
	-C "$project_root/test/network/udp-impairment-proxy" build \
	-o "$proxy_bin" \
	.

supervisor_start_quiet \
	"orchestrator" \
	"$artifact_dir/orchestrator.log" \
	"$project_root" \
	"$script_dir/run_orchestrator.sh" \
	"--default-zone" "$zone_id" \
	"--game-server-port" "$orchestrator_game_port" \
	"--client-port" "$orchestrator_client_port" \
	"--health-port" "$orchestrator_health_port" \
	"--transfer-ttl" "$orchestrator_transfer_ttl"

wait_for_url "orchestrator readiness" "http://127.0.0.1:$orchestrator_health_port/readyz" 10

supervisor_start_quiet \
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
	"--max-peers" "$((client_count + 8))" \
	"--advertise-address" "127.0.0.1" \
	"--orchestrator-url" "ws://127.0.0.1:$orchestrator_game_port/ws"

wait_for_zone_registration "http://127.0.0.1:$orchestrator_health_port/healthz" "$zone_id" 15

: >"$artifact_dir/clients.csv"
printf 'index,rtt_ms,jitter_ms,loss_percent,proxy_port,observer,windowed,movement_seed\n' \
	>"$artifact_dir/clients.csv"
batch_start=0
for ((index = 0; index < client_count; index++)); do
	rtt_ms=$((minimum_rtt_ms + index * (maximum_rtt_ms - minimum_rtt_ms) / (client_count - 1)))
	jitter_ms=$((rtt_ms / 10))
	seed=$((base_seed + index * 17))
	observer=0
	windowed=0
	if (( index == 0 || index == client_count - 1 )); then
		observer=1
		if (( headless == 0 )); then
			windowed=1
		fi
	fi
	client_rtts+=("$rtt_ms")
	client_jitters+=("$jitter_ms")
	printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
		"$index" "$rtt_ms" "$jitter_ms" "$loss_percent" "${proxy_ports[$index]}" \
		"$observer" "$windowed" "$seed" >>"$artifact_dir/clients.csv"

	supervisor_start_quiet \
		"scale-proxy-$index" \
		"$artifact_dir/proxy-$index.log" \
		"$project_root" \
		"$proxy_bin" \
		"--listen-address" "127.0.0.1" \
		"--listen-port" "${proxy_ports[$index]}" \
		"--target-address" "127.0.0.1" \
		"--target-port" "$zone_port" \
		"--up-delay" "$((rtt_ms / 2))ms" \
		"--down-delay" "$((rtt_ms / 2))ms" \
		"--up-jitter" "${jitter_ms}ms" \
		"--down-jitter" "${jitter_ms}ms" \
		"--up-loss-percent" "$loss_percent" \
		"--down-loss-percent" "$loss_percent" \
		"--seed" "$seed" \
		"--ready-file" "$artifact_dir/proxy-$index-ready.json" \
		"--stats-file" "$artifact_dir/proxy-$index-stats.json"
	proxy_pids+=("$started_pid")
done

if ! wait_for_all_proxy_readiness 20; then
	report_failure 1
fi

for ((index = 0; index < client_count; index++)); do
	display_args=("--headless")
	if (( headless == 0 && index == 0 )); then
		display_args=("--windowed" "--position" "40,40")
	elif (( headless == 0 && index == client_count - 1 )); then
		display_args=("--windowed" "--position" "700,40")
	fi
	profile="client-$index:rtt:${client_rtts[$index]}ms,jitter:${client_jitters[$index]}ms,loss:${loss_percent}%"
	movement_seed=$((base_seed + 100000 + index * 97))
	supervisor_start_quiet \
		"network-scale-$index" \
		"$artifact_dir/client-$index.log" \
		"$project_root" \
		timeout "${process_timeout_seconds}s" \
		env "ORHYN_GODOT_RUNTIME_DIR=$artifact_dir/runtime-client-$index" \
		"$script_dir/godot-sandboxed.sh" \
		"${display_args[@]}" \
		"--path" "./godot" \
		"--scene" "res://projects/e2e/e2e_client.tscn" \
		"--" \
		"--orchestrator-url" "ws://127.0.0.1:$orchestrator_client_port/ws" \
		"--username" "e2e_network_scale_${run_id}_$index" \
		"--zone" "$zone_id" \
		"--suite" "network_scale" \
		"--coordination-dir" "$coordination_dir" \
		"--timeout" "$client_timeout_seconds" \
		"--zone-connect-address" "127.0.0.1" \
		"--zone-connect-port" "${proxy_ports[$index]}" \
		"--client-index" "$index" \
		"--client-count" "$client_count" \
		"--network-profile" "$profile" \
		"--movement-seed" "$movement_seed" \
		"--movement-duration" "$movement_duration_seconds" \
		"--metrics-drain" "$metrics_drain_seconds" \
		"--metric-sample-capacity" "$metric_sample_capacity" \
		"--min-remote-motion-samples" "$minimum_remote_motion_samples" \
		"--result-file" "$artifact_dir/client-$index-result.json"
	client_pids+=("$started_pid")
	if (( (index + 1) % startup_batch_size == 0 || index == client_count - 1 )); then
		if ! wait_for_client_range_phase \
				"connected" "$batch_start" "$index" "$client_timeout_seconds"; then
			report_failure 1
		fi
		batch_start=$((index + 1))
	fi
done

printf '%s\n' \
	"run_id=$run_id" \
	"artifact_dir=$artifact_dir" \
	"zone_id=$zone_id" \
	"client_count=$client_count" \
	"movement_duration_seconds=$movement_duration_seconds" \
	"metrics_drain_seconds=$metrics_drain_seconds" \
	"headless=$headless" \
	"startup_batch_size=$startup_batch_size" \
	"orchestrator_transfer_ttl=$orchestrator_transfer_ttl" \
	"rtt_range_ms=$minimum_rtt_ms-$maximum_rtt_ms" \
	"loss_percent=$loss_percent" \
	"minimum_remote_motion_samples=$minimum_remote_motion_samples" \
	"metric_sample_capacity=$metric_sample_capacity" \
	>"$artifact_dir/run.env"

if ! wait_for_all_client_phase "ready" "$client_timeout_seconds"; then
	report_failure 1
fi
write_barrier "network-scale-arm.json"
if ! wait_for_all_client_phase "armed" "$client_timeout_seconds"; then
	report_failure 1
fi
write_barrier "network-scale-start.json"
if ! wait_for_all_client_phase \
		"movement-done" "$((client_timeout_seconds + movement_duration_seconds))"; then
	report_failure 1
fi
sleep "$metrics_drain_seconds"
write_barrier "network-scale-finish.json"

result_status=0
set +e
for ((index = 0; index < client_count; index++)); do
	wait "${client_pids[$index]}"
	status="$?"
	_supervisor_remove_pid "${client_pids[$index]}"
	if (( status != 0 )); then
		echo "Client $index exited with status $status." >&2
		result_status=1
	fi
done
set -e

for ((index = 0; index < client_count; index++)); do
	result_file="$artifact_dir/client-$index-result.json"
	if [[ ! -s "$result_file" ]] || ! rg -q '"ok":true' "$result_file"; then
		echo "Client $index did not report success." >&2
		result_status=1
	fi
done
if (( result_status != 0 )); then
	report_failure 1
fi

print_scale_summary
trap - EXIT
supervisor_stop_all
echo "Network-scale profiles: $artifact_dir/clients.csv"
echo "Network-scale E2E artifacts: $artifact_dir"
