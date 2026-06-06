class_name RuntimeMain
extends Node

const RUNTIME_CLIENT := "client"
const RUNTIME_GAME_SERVER := "game-server"
const RUNTIME_ORCHESTRATOR := "orchestrator"

const CLIENT_SCENE_PATH := "res://projects/client/src/screens/login_screen.tscn"
const GAME_SERVER_SCENE_PATH := "res://projects/game-server/src/zones/zone.tscn"
const ORCHESTRATOR_SCENE_PATH := "res://projects/orchestrator/orchestrator.tscn"


func _ready() -> void:
	var runtime: String = detect_runtime()
	var scene_path: String = get_scene_path_for_runtime(runtime)
	Log.info("area=Boot message=%s values=%s" % [str("Runtime main dispatch"), str({
		"runtime": runtime,
		"scene": scene_path,
		"features": _get_runtime_feature_snapshot(),
		"user_args": OS.get_cmdline_user_args(),
	})])
	call_deferred("_change_to_runtime_scene", scene_path, runtime)


func _change_to_runtime_scene(scene_path: String, runtime: String) -> void:
	var err: Error = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		Log.error("area=Boot message=%s values=%s" % [str("Runtime main scene dispatch failed"), str({
			"runtime": runtime,
			"scene": scene_path,
			"error": error_string(err),
		})])
		get_tree().quit(1)


func detect_runtime() -> String:
	var runtime_from_user_args: String = get_runtime_from_args(OS.get_cmdline_user_args())
	if not runtime_from_user_args.is_empty():
		return runtime_from_user_args

	var runtime_from_all_args: String = get_runtime_from_args(OS.get_cmdline_args())
	if not runtime_from_all_args.is_empty():
		return runtime_from_all_args

	if OS.has_feature(RUNTIME_ORCHESTRATOR):
		return RUNTIME_ORCHESTRATOR
	if OS.has_feature(RUNTIME_GAME_SERVER) or OS.has_feature("game_server"):
		return RUNTIME_GAME_SERVER
	if OS.has_feature(RUNTIME_CLIENT):
		return RUNTIME_CLIENT
	return RUNTIME_CLIENT


static func get_runtime_from_args(args: PackedStringArray) -> String:
	for index: int in range(args.size()):
		var arg: String = args[index]
		if arg == "--runtime" and index + 1 < args.size():
			return normalize_runtime(args[index + 1])
		if arg.begins_with("--runtime="):
			return normalize_runtime(arg.trim_prefix("--runtime="))
		if arg == "--game-server" or arg == "--game_server":
			return RUNTIME_GAME_SERVER
		if arg == "--client":
			return RUNTIME_CLIENT
	return ""


static func normalize_runtime(raw_runtime: String) -> String:
	var runtime: String = raw_runtime.strip_edges().to_lower().replace("_", "-")
	match runtime:
		RUNTIME_CLIENT:
			return RUNTIME_CLIENT
		RUNTIME_GAME_SERVER, "server", "zone-server", "zone":
			return RUNTIME_GAME_SERVER
		RUNTIME_ORCHESTRATOR, "orch":
			return RUNTIME_ORCHESTRATOR
	return ""


static func get_scene_path_for_runtime(runtime: String) -> String:
	match normalize_runtime(runtime):
		RUNTIME_GAME_SERVER:
			return GAME_SERVER_SCENE_PATH
		RUNTIME_ORCHESTRATOR:
			return ORCHESTRATOR_SCENE_PATH
	return CLIENT_SCENE_PATH


func _get_runtime_feature_snapshot() -> Dictionary:
	return {
		RUNTIME_CLIENT: OS.has_feature(RUNTIME_CLIENT),
		RUNTIME_GAME_SERVER: OS.has_feature(RUNTIME_GAME_SERVER),
		"game_server": OS.has_feature("game_server"),
		RUNTIME_ORCHESTRATOR: OS.has_feature(RUNTIME_ORCHESTRATOR),
	}
