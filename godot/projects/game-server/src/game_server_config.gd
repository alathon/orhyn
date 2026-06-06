class_name GameServerConfig
extends Node

const DEFAULT_BIND_ADDRESS: String = "0.0.0.0"
const DEFAULT_ADVERTISE_ADDRESS: String = "127.0.0.1"
const DEFAULT_PORT: int = 4242
const DEFAULT_MAX_PEERS: int = 32
const DEFAULT_ZONE_NAME: String = "mvp"
const DEFAULT_ORCHESTRATOR_URL: String = "ws://127.0.0.1:9000/ws"

var bind_address: String = DEFAULT_BIND_ADDRESS
var advertise_address: String = DEFAULT_ADVERTISE_ADDRESS
var port: int = DEFAULT_PORT
var max_peers: int = DEFAULT_MAX_PEERS
var zone_name: String = DEFAULT_ZONE_NAME
var orchestrator_url: String = DEFAULT_ORCHESTRATOR_URL

func _init() -> void:
	_apply_cmdline_args(OS.get_cmdline_args())
	_apply_cmdline_args(OS.get_cmdline_user_args())

func _apply_cmdline_args(args: PackedStringArray) -> void:
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		var value: String = _arg_value(args, i)

		match arg:
			"--bind-address":
				if not value.is_empty():
					bind_address = value
					i += 1
			"--advertise-address":
				if not value.is_empty():
					advertise_address = value
					i += 1
			"--port":
				if not value.is_empty():
					port = int(value)
					i += 1
			"--max-peers":
				if not value.is_empty():
					max_peers = int(value)
					i += 1
			"--zone", "--zone-name", "--zone-id":
				if not value.is_empty():
					zone_name = value
					i += 1
			"--orchestrator-url", "--orchestrator":
				if not value.is_empty():
					orchestrator_url = value
					i += 1
		i += 1

func _arg_value(args: PackedStringArray, index: int) -> String:
	if index + 1 >= args.size():
		return ""
	var value: String = args[index + 1]
	if value.begins_with("--"):
		return ""
	return value

func describe() -> Dictionary:
	return {
		"bind_address": bind_address,
		"advertise_address": advertise_address,
		"port": port,
		"max_peers": max_peers,
		"zone_name": zone_name,
		"orchestrator_url": orchestrator_url,
	}
