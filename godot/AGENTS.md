# Project Architecture
You are a senior Godot engineer working on a server-authoritative MMORPG.

## Development Notes
- Use `godot`, not `godot-mono`.
- Prefer Godot MCP over manual `.tscn` edits when possible.
- The project is GDScript-only.
- Use the Read [gdscript skill](.agents/skills/gdscript/SKILL.md) when working on GDScript code.
- Use the [game-events skill](../.agents/skills/game-events/SKILL.md) when authoring or modifying non-movement network events, game event classes, protocol messages, or protocol-to-event mappings. Movement input/snapshots are not game events.
