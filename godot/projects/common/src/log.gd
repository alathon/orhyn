class_name Log extends Logger

enum Event {
	DEBUG,
	INFO,
	WARN,
	ERROR,
	CRITICAL,
	FORCE_FLUSH,
}

const _LOG_DIR := "user://"
const _LOG_EXTENSION := "log"

const _MAX_LOG_FILES: int = 5
const _MAX_BUFFER_SIZE: int = 10
const _FLUSH_EVENTS: PackedByteArray = [
	Event.ERROR,
	Event.CRITICAL,
	Event.FORCE_FLUSH,
]
const EVENT_COLORS: Dictionary[Event, String] = {
	Event.DEBUG: "deep_sky_blue",
	Event.INFO: "lime_green",
	Event.WARN: "gold",
	Event.ERROR: "tomato",
	Event.CRITICAL: "crimson",
}

static var _buffer_size: int
static var _event_strings: PackedStringArray = Event.keys()

static var _log_file: FileAccess
static var _log_file_path: String
static var _is_valid: bool
static var _mutex := Mutex.new()
static var _console_echoes: Dictionary[String, int] = {}

static func _static_init() -> void:
	_log_file = _create_log_file()
	_is_valid = _log_file and _log_file.is_open()
	if _is_valid:
		OS.add_logger(Log.new())
		_remove_old_log_files()

static func _remove_old_log_files() -> void:
	var log_file_paths: Array[String]
	var current_log_path := ProjectSettings.globalize_path(_log_file_path)
	for file: String in DirAccess.get_files_at(_LOG_DIR):
		if file.get_extension().to_lower() == _LOG_EXTENSION:
			var path := ProjectSettings.globalize_path(_LOG_DIR.path_join(file))
			if path != current_log_path:
				log_file_paths.append(path)
	log_file_paths.sort()
	var max_old_log_files := maxi(0, _MAX_LOG_FILES - 1)
	while log_file_paths.size() > max_old_log_files:
		var path: String = log_file_paths.pop_front()
		var err := DirAccess.remove_absolute(path)
		if err:
			warn("Failed to clean up old log (%s): %s" % [error_string(err), path])
		else:
			info("Cleaned up old log: %s" % path)

static func _create_log_file() -> FileAccess:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file_name := "%s.%s" % [timestamp, _LOG_EXTENSION]
	var file_path := _LOG_DIR.path_join(file_name)
	_log_file_path = file_path
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	return file

static func _get_gdscript_backtrace(script_backtraces: Array[ScriptBacktrace]) -> String:
	var gdscript := script_backtraces.find_custom(func(backtrace: ScriptBacktrace) -> bool:
		return backtrace.get_language_name() == "GDScript")
	return "Backtrace N/A" if gdscript == -1 else str(script_backtraces[gdscript])

static func _format_log_message(message: String, event: Event) -> String:
	return "[{time}] {event}: {message}".format({
		"time": Time.get_time_string_from_system(),
		"event": _event_strings[event],
		"message": message,
	})

static func _add_message_to_file(message: String, event: Event) -> void:
	_mutex.lock()
	if _is_valid:
		if not message.is_empty():
			_is_valid = _log_file.store_line(message)
			_buffer_size += 1
		if _buffer_size >= _MAX_BUFFER_SIZE or event in _FLUSH_EVENTS:
			_log_file.flush()
			_buffer_size = 0
	_mutex.unlock()

static func _print_event(message: String, event: Event) -> void:
	if DisplayServer.get_name() != "headless" and OS.has_feature("editor"):
		var message_lines := message.split("\n")
		message_lines[0] = "[b][color=%s]%s[/color][/b]" % [EVENT_COLORS[event], message_lines[0]]
		var rich_message := "[lang=tlh]%s[/lang]" % "\n".join(message_lines)
		print_rich(rich_message)
	else:
		_remember_console_echo(message)
		print(message)

static func _remember_console_echo(message: String) -> void:
	_mutex.lock()
	_console_echoes[message] = int(_console_echoes.get(message, 0)) + 1
	_mutex.unlock()

static func _consume_console_echo(message: String) -> bool:
	_mutex.lock()
	var count := int(_console_echoes.get(message, 0))
	if count > 1:
		_console_echoes[message] = count - 1
	elif count == 1:
		_console_echoes.erase(message)
	_mutex.unlock()
	return count > 0

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if not _is_valid:
		return
	var event := Event.WARN if error_type == ERROR_TYPE_WARNING else Event.ERROR
	var message := "[{time}] {event}: {rationale}\n{code}\n{file}:{line} @ {function}()".format({
		"time": Time.get_time_string_from_system(),
		"event": _event_strings[event],
		"rationale": rationale,
		"code": code,
		"file": file,
		"line": line,
		"function": function,
 	})
	if event == Event.ERROR:
		message += '\n' + _get_gdscript_backtrace(script_backtraces)
	_add_message_to_file(message, event)

func _log_message(message: String, log_message_error: bool) -> void:
	if not _is_valid or message.begins_with("[lang=tlh]"):
		return
	var trimmed_message := message.trim_suffix('\n')
	if _consume_console_echo(trimmed_message):
		return
	var event := Event.ERROR if log_message_error else Event.INFO
	message = _format_log_message(trimmed_message, event)
	_add_message_to_file(message, event)

static func debug(message: String) -> void:
	var event := Event.DEBUG
	message = _format_log_message(message, event)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func info(message: String) -> void:
	var event := Event.INFO
	message = _format_log_message(message, event)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func warn(message: String) -> void:
	var event := Event.WARN
	message = _format_log_message(message, event)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func error(message: String) -> void:
	var event := Event.ERROR
	message = _format_log_message(message, event)
	var script_backtraces := Engine.capture_script_backtraces()
	message += '\n' + _get_gdscript_backtrace(script_backtraces)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func critical(message: String) -> void:
	var event := Event.CRITICAL
	message = _format_log_message(message, event)
	var script_backtraces := Engine.capture_script_backtraces()
	message += '\n' + _get_gdscript_backtrace(script_backtraces)
	_add_message_to_file(message, event)
	_print_event(message, event)

static func force_flush() -> void:
	_add_message_to_file("", Event.FORCE_FLUSH)
