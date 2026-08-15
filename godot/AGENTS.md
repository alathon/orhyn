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
- See the short [network gameplay events guide](projects/common/src/game_events/README.md) for file locations and the codec/event checklist.
- Add or update E2E tests for significant gameplay or client/server features as part of building them. Significant features include new networked gameplay flows, changes to login or zone-entry behavior, replicated state, movement, equipment, multi-client visibility, or anything whose correctness depends on real orchestrator, zone server, ENet, protocol routing, and client observation working together. Keep each gameplay test set in its own script under `res://projects/e2e/tests/`, wire it into the E2E runner scene, and verify with `make e2e` when Godot and Go are available. E2E tests should trigger client/game action nodes that a UI could call, then assert observed outcomes; direct protocol message construction and raw network packet assertions belong in focused unit/protocol tests unless the E2E explicitly targets protocol compatibility.
