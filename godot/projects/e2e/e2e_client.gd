extends Node

const DEFAULT_RESULT_FILE: String = ""

@onready var _session: E2ESession = $E2ESession
@onready var _runner: E2ETestRunner = $E2ETestRunner

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var config: Dictionary = {
		"orchestrator_url": _get_arg("--orchestrator-url", OrchestratorAPI.DEFAULT_ORCHESTRATOR_URL),
		"username": _get_arg("--username", "e2e_boot"),
		"zone_id": _get_arg("--zone", "mvp"),
		"timeout_seconds": float(_get_arg("--timeout", "10")),
		"suite": _get_arg("--suite", "gameplay"),
		"coordination_dir": _get_arg("--coordination-dir", ""),
		"client_role": _get_arg("--client-role", ""),
		"zone_connect_address": _get_arg("--zone-connect-address", ""),
		"zone_connect_port": int(_get_arg("--zone-connect-port", "0")),
		"network_profile": _get_arg("--network-profile", "unspecified"),
		"movement_duration_seconds": float(_get_arg("--movement-duration", "20")),
		"metrics_drain_seconds": float(_get_arg("--metrics-drain", "1")),
		"minimum_remote_motion_samples": int(_get_arg("--min-remote-motion-samples", "1")),
	}
	var result_file: String = _get_arg("--result-file", DEFAULT_RESULT_FILE)

	var session_started: bool = await _session.start(config)
	var result: Dictionary
	if session_started:
		result = await _runner.run(config)
	else:
		result = {
			"ok": false,
			"suite": str(config.get("suite", "gameplay")),
			"tests": [],
			"failure_step": "session:%s" % _session.failure_step,
			"failure_reason": _session.failure_reason,
			"failure_details": _session.failure_details,
		}
	var ok: bool = bool(result.get("ok", false))
	_write_result(result_file, result)
	print("E2E_RESULT " + JSON.stringify(result))

	_session.close()
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)

func _get_arg(name: String, default_value: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		var arg: String = args[index]
		if arg == name and index + 1 < args.size():
			return args[index + 1]
		if arg.begins_with(name + "="):
			return arg.trim_prefix(name + "=")
	return default_value

func _write_result(path: String, result: Dictionary) -> void:
	if path.strip_edges().is_empty():
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write E2E result file: %s error=%s" % [path, error_string(FileAccess.get_open_error())])
		return

	file.store_string(JSON.stringify(result) + "\n")
	file.close()
