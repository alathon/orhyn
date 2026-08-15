class_name E2ETestRunner
extends Node

@export var session: E2ESession

func run(config: Dictionary = {}) -> Dictionary:
	var requested_suite: String = str(config.get("suite", "gameplay"))
	var tests: Array[Dictionary] = []
	var ok: bool = true
	var failure_step: String = ""
	var failure_reason: String = ""

	for child: Node in get_children():
		var test: E2ETestCase = child as E2ETestCase
		if test == null:
			continue
		if test.suite_name != requested_suite:
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

	if tests.is_empty():
		ok = false
		failure_step = "select_suite"
		failure_reason = "No E2E tests are configured for suite '%s'." % requested_suite

	return {
		"ok": ok,
		"suite": requested_suite,
		"tests": tests,
		"failure_step": failure_step,
		"failure_reason": failure_reason,
	}
