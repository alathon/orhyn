class_name E2ETestCase
extends Node

@export var test_name: String = ""
@export var timeout_seconds: float = E2ESession.DEFAULT_TIMEOUT_SECONDS

func run(_session: E2ESession, _config: Dictionary = {}) -> Dictionary:
	return passed()

func passed(details: Dictionary = {}) -> Dictionary:
	return {
		"name": _get_test_name(),
		"ok": true,
		"details": details,
	}

func failed(step: String, reason: String, details: Dictionary = {}) -> Dictionary:
	push_error("E2E test failed: %s step=%s reason=%s details=%s" % [
		_get_test_name(),
		step,
		reason,
		str(details),
	])
	return {
		"name": _get_test_name(),
		"ok": false,
		"failure_step": step,
		"failure_reason": reason,
		"details": details,
	}

func _get_test_name() -> String:
	if not test_name.strip_edges().is_empty():
		return test_name
	return name
