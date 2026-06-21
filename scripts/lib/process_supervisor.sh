#!/usr/bin/env bash

supervisor_pids=()
supervisor_names=()
supervisor_logs=()
supervisor_stopping=0
started_pid=

supervisor_start() {
    local name="$1"
    local log_file="$2"
    local workdir="$3"
    shift 3

    mkdir -p "$(dirname -- "$log_file")"
    : >"$log_file"

    (
        cd "$workdir" || exit 1
        if command -v stdbuf >/dev/null 2>&1; then
            exec stdbuf -oL -eL "$@"
        fi
        exec "$@"
    ) > >(tee -a "$log_file" | sed -u "s/^/[$name] /") 2>&1 &

    started_pid="$!"
    supervisor_pids+=("$started_pid")
    supervisor_names+=("$name")
    supervisor_logs+=("$log_file")

    echo "Started $name pid=$started_pid log=$log_file"
}

_supervisor_name_for_pid() {
    local pid="$1"
    local i

    for i in "${!supervisor_pids[@]}"; do
        if [[ "${supervisor_pids[$i]}" == "$pid" ]]; then
            printf '%s\n' "${supervisor_names[$i]}"
            return 0
        fi
    done

    printf 'unknown\n'
}

_supervisor_remove_pid() {
    local pid="$1"
    local new_pids=()
    local new_names=()
    local new_logs=()
    local i

    for i in "${!supervisor_pids[@]}"; do
        if [[ "${supervisor_pids[$i]}" == "$pid" ]]; then
            continue
        fi

        new_pids+=("${supervisor_pids[$i]}")
        new_names+=("${supervisor_names[$i]}")
        new_logs+=("${supervisor_logs[$i]}")
    done

    supervisor_pids=("${new_pids[@]}")
    supervisor_names=("${new_names[@]}")
    supervisor_logs=("${new_logs[@]}")
}

supervisor_stop_all() {
    local pid

    if (( supervisor_stopping )); then
        return 0
    fi
    supervisor_stopping=1

    trap - INT TERM EXIT

    if (( ${#supervisor_pids[@]} == 0 )); then
        return 0
    fi

    echo "Stopping ${#supervisor_pids[@]} process(es)..."

    for pid in "${supervisor_pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done

    sleep 2

    for pid in "${supervisor_pids[@]}"; do
        kill -KILL "$pid" 2>/dev/null || true
    done

    for pid in "${supervisor_pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    supervisor_pids=()
    supervisor_names=()
    supervisor_logs=()
}

supervisor_wait() {
    local exited_pid
    local status
    local name

    while (( ${#supervisor_pids[@]} > 0 )); do
        exited_pid=
        wait -n -p exited_pid "${supervisor_pids[@]}"
        status="$?"

        if [[ -z "${exited_pid:-}" ]]; then
            return 0
        fi

        name="$(_supervisor_name_for_pid "$exited_pid")"
        _supervisor_remove_pid "$exited_pid"

        echo "Exited $name pid=$exited_pid status=$status"

        if [[ "$name" == "orchestrator" ]]; then
            echo "Orchestrator exited; stopping remaining processes."
            supervisor_stop_all
            return "$status"
        fi

        if (( status != 0 )); then
            echo "$name exited with status $status; stopping remaining processes." >&2
            supervisor_stop_all
            return "$status"
        fi
    done

    return 0
}

supervisor_install_traps() {
    trap 'supervisor_stop_all; exit 130' INT
    trap 'supervisor_stop_all; exit 143' TERM
    trap 'supervisor_stop_all' EXIT
}
