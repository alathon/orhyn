class_name ClientLoadingCoordinator
extends Node

signal loading_started(session_id: int, context: Dictionary)
signal loading_progress_changed(session_id: int, progress: float, gates: Dictionary)
signal gate_changed(gate_id: StringName, gate: Dictionary)
signal loading_completed(session_id: int, context: Dictionary)
signal loading_canceled(session_id: int, reason: String)
signal loading_failed(session_id: int, reason: String)

var _next_session_id: int = 1
var _session_id: int = 0
var _loading: bool = false
var _context: Dictionary = {}
var _gates: Dictionary = {}
var _progress: float = 0.0

func begin_zone_transfer(target_zone_id: String, transfer_token: String = "") -> int:
	_loading = true
	_session_id = _next_session_id
	_next_session_id += 1
	_context = {
		"target_zone_id": target_zone_id,
		"transfer_token": transfer_token,
		"started_msec": Time.get_ticks_msec(),
		"reason": "zone_transfer",
	}
	_gates.clear()
	_progress = 0.0
	loading_started.emit(_session_id, _context.duplicate(true))
	_emit_progress()
	return _session_id

func add_gate(gate_id: StringName, label: String, weight: float = 1.0, required: bool = true) -> void:
	if not _loading:
		return

	_gates[gate_id] = {
		"id": gate_id,
		"label": label,
		"weight": maxf(weight, 0.0),
		"required": required,
		"progress": 0.0,
		"complete": false,
		"failed": false,
		"detail": "",
		"failure_reason": "",
	}
	_emit_gate_changed(gate_id)
	_recalculate_progress()

func set_gate_progress(gate_id: StringName, progress: float, detail: String = "") -> void:
	if not _loading or not _gates.has(gate_id):
		return

	var gate: Dictionary = _gates[gate_id]
	if bool(gate.get("complete", false)) or bool(gate.get("failed", false)):
		return

	gate["progress"] = clampf(progress, 0.0, 1.0)
	gate["detail"] = detail
	_gates[gate_id] = gate
	_emit_gate_changed(gate_id)
	_recalculate_progress()

func complete_gate(gate_id: StringName, detail: String = "") -> void:
	if not _loading or not _gates.has(gate_id):
		return

	var gate: Dictionary = _gates[gate_id]
	if bool(gate.get("failed", false)):
		return

	gate["progress"] = 1.0
	gate["complete"] = true
	gate["detail"] = detail
	_gates[gate_id] = gate
	_emit_gate_changed(gate_id)
	_recalculate_progress()
	_check_completion()

func fail_gate(gate_id: StringName, reason: String) -> void:
	if not _loading or not _gates.has(gate_id):
		return

	var gate: Dictionary = _gates[gate_id]
	gate["failed"] = true
	gate["failure_reason"] = reason
	gate["detail"] = reason
	_gates[gate_id] = gate
	_emit_gate_changed(gate_id)
	_recalculate_progress()

	if bool(gate.get("required", true)):
		_loading = false
		loading_failed.emit(_session_id, reason)

func finish_loading(detail: String = "Ready") -> void:
	if not _loading:
		return

	_progress = 1.0
	_context["completed_detail"] = detail
	_loading = false
	_emit_progress()
	loading_completed.emit(_session_id, _context.duplicate(true))

func cancel_loading(reason: String = "Canceled") -> void:
	if not _loading:
		return

	_loading = false
	_context["canceled_reason"] = reason
	_emit_progress()
	loading_canceled.emit(_session_id, reason)

func is_loading() -> bool:
	return _loading

func get_progress() -> float:
	return _progress

func get_session_id() -> int:
	return _session_id

func get_context() -> Dictionary:
	return _context.duplicate(true)

func get_gate_snapshot() -> Dictionary:
	return _gates.duplicate(true)

func _recalculate_progress() -> void:
	var total_weight: float = 0.0
	var weighted_progress: float = 0.0
	for gate_id: StringName in _gates.keys():
		var gate: Dictionary = _gates[gate_id]
		var weight: float = float(gate.get("weight", 1.0))
		total_weight += weight
		weighted_progress += weight * float(gate.get("progress", 0.0))

	_progress = weighted_progress / total_weight if total_weight > 0.0 else 0.0
	_emit_progress()

func _check_completion() -> void:
	if not _loading:
		return

	var has_required_gate: bool = false
	for gate_id: StringName in _gates.keys():
		var gate: Dictionary = _gates[gate_id]
		if not bool(gate.get("required", true)):
			continue

		has_required_gate = true
		if bool(gate.get("failed", false)) or not bool(gate.get("complete", false)):
			return

	if has_required_gate:
		finish_loading("Ready")

func _emit_gate_changed(gate_id: StringName) -> void:
	var gate: Dictionary = _gates[gate_id]
	gate_changed.emit(gate_id, gate.duplicate(true))

func _emit_progress() -> void:
	loading_progress_changed.emit(_session_id, _progress, get_gate_snapshot())
