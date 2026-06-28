# Project Architecture
You are a senior Godot engineer working on a server-authoritative MMORPG.

## Development Notes
- Use `godot`, not `godot-mono`.
- When running Godot from automation or an agent sandbox, use `scripts/godot-sandboxed.sh` from the repo root instead of invoking `godot` directly. It points Godot's user data, config, cache, and logs at a writable runtime directory so headless checks do not crash when the normal user data path is sandboxed. Example: `scripts/godot-sandboxed.sh --headless --path godot --quit`.
- To run the GUT suite from automation, use `scripts/godot-sandboxed.sh --headless --path godot -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`.
- Override the sandbox runtime location with `ORHYN_GODOT_RUNTIME_DIR=/path/to/writable/dir` if `/tmp/orhyn-godot-runtime` is not appropriate.
- Prefer Godot MCP over manual `.tscn` edits when possible.
- The project is GDScript-only.
- Use the Read [gdscript skill](.agents/skills/gdscript/SKILL.md) when working on GDScript code.
- Use the [game-events skill](../.agents/skills/game-events/SKILL.md) when authoring or modifying non-movement network events, game event classes, protocol messages, or protocol-to-event mappings. Movement input/snapshots are not game events.
