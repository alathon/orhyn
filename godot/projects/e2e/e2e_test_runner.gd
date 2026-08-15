class_name E2ETestRunner
extends Node

@export var session: E2ESession

func run(config: Dictionary = {}) -> Dictionary:
	var tests: Array[Dictionary] = []
	var ok: bool = true
	var failure_step: String = ""
	var failure_reason: String = ""

	for child: Node in get_children():
		var test: E2ETestCase = child as E2ETestCase
		if test == null:
			continue

		var result: Dictionary = await test.run(session, config)
		tests.append(result)

		if bool(result.get("ok", false)):
			continue

		ok = false
		failure_step = "%s:%s" % [
			str(result.get("name", child.name)),
			str(result.get("failure_step", "")),
		]
		failure_reason = str(result.get("failure_reason", "E2E test failed."))
		break

	return {
		"ok": ok,
		"suite": "gameplay",
		"tests": tests,
		"failure_step": failure_step,
		"failure_reason": failure_reason,
	}
