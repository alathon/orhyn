---
name: gdscript
description: Write GDScript code
disable-model-invocation: false
---

# References to other components

- Use explicit scene contracts instead of discovering dependencies at runtime.
- Required child in the same scene: use a typed `@onready var` with `%` for a unique name or `$` for a stable child path:
  `@onready var body: PhysicsBody = $PhysicsBody`
  `@onready var model_manager: ModelManager = %ModelContainer`
- Required dependency supplied by the scene or parent: use a typed `@export var` and wire it in the `.tscn`/editor:
  `@export var entity_root_node: BaseEntity`
  Do not fill exported vars in `_ready()` with `get_node_or_null()`, `get_parent()`, owner lookup, or fallback paths.
- Do not use a plain `var` plus `_ready()` to wire stable scene dependencies. If a required value comes from the local scene tree, use `@onready`; if another scene must provide it, use `@export`. Plain typed vars may hold node references when those references are resolved later from signals, observables, spawning, or other dynamic lifecycles.
- Treat required references as required. Do not scatter null checks around every use of mandatory `@onready` and `@export` refs; the scene is responsible for making them available. Null-check optional or dynamic refs at use sites when they are set later by signals, observables, spawning, etc. If mandatory refs need defensive validation, check once in `_ready()` and `push_error()` when the scene contract is broken.
- Do not instantiate scene/service nodes with `new()` in production code when they can be added to a stable `.tscn` scene.
  Add them to the scene and reference them with `@onready var _service: ServiceType = %ServiceName` instead.
- Don't use `setup()` or `bind()` methods to accomplish the above.

# Preloads

- Do not preload(), except to reference the `Proto` messages, e.g., `const Proto = preload("res://projects/common/src/proto/packets.gd")`.
- You can use references to any class_name in the whole project, without preload()'ing it.

# Separation of concerns
Keep logic in .gd files, data in .tres files:

```
src/
  spells/
    spell_resource.gd      # Class definition + logic
    spell_effect.gd        # Effect logic
resources/
  spells/
    fireball.tres          # Data only, references scripts
    ice_spike.tres         # Data only
```

# Component-Based Architecture
Break functionality into focused components:

Player (CharacterBody3D)
├─ Attributes (Node)           # Component
├─ Inventory (Node)            # Component
└─ StateMachine (Node)         # Component
    ├─ IdleState (Node)
    ├─ MoveState (Node)
    └─ AttackState (Node)

Benefits:

- Each component is a small, focused file
- Easy to understand and modify
- Clear responsibilities
- Reusable across different entities of similar types

# Signal-driven communication
Use signals for loose coupling:

```
signal health_changed(current, max)
signal death()

# Parent connects to signals
@onready var health_attribute: HealthAttribute = $HealthAttribute

func _ready():
    health_attribute.health_changed.connect(_on_health_changed)
    health_attribute.death.connect(_on_death)
```

Benefits:

- No tight coupling between systems
- Easy to add new listeners
- Self-documenting (signals show available events)
- UI can connect without modifying game logic

# Godot resource files (.tres, .tscn)
- NEVER manually assign or generate uid:// fields—Godot fills these in automatically

# Connecting @exports in scene files
When a script uses @export var some_node: SomeNodeType, you can assign it via a .tscn file:

```
[node name="MyNode" type="Node3D" parent="." node_paths=PackedStringArray("player", "camera")]
script = ExtResource("1_abc123")
player = NodePath("../Player")
camera = NodePath("CameraPivot/Camera3D")
```

# Import new files with Godot CLI

After creating a new file, run the Godot CLI with `--import` to help them get picked up by the editor:
```
godot --headless --import
```
This should be run in `main/`, the Godot project root directory where `project.godot` is located. From the repo root, use `godot --headless --path main --import`. Remember that any folder containing .gdignore will be skipped during import.

# Duck-type or strongly type

- NEVER do `var a := b`. Either do:
  - Strongly typed: `var a: Type = b` OR
  - Duck-typed: `var a = b`
- Prefer declaration types over casts. Do not write `var a = b as Type`; write `var a: Type = b`.

If casting with `var a: Type = b` doesn't seem to work, it is usually a sign that a .gdscript file is not compiling successfully.

# Don't look up the scene tree if you can avoid it

- Don't walk *upward* in the scene tree, especially through multiple parents. It is okay to look into children with stable paths, use unique accessors, use exports for parent-provided references, and use globals:
	- Bad: @onready var _zone = get_owner()
	- Bad: @onready var _zone = get_parent().get_parent()
	- Bad: @onready var _otherThing = $"../../Something"
	- Bad: exported `_zone` assigned from `get_node_or_null()` in `_ready()`
	- Good: @onready var _unique: Zone = %UniqueAccessorInScene
	- Good: @onready var _downward: Label = $MyThing/MyOtherThing
	- Good: @export var _zone: Zone
	- Good: const thing = Globals.GCD_COOLDOWN

- Don't use `get_node_or_null()` or `find_child()` to repair missing required wiring. If a required node/export is missing, fix the scene.
- Don't look for nodes every frame or when you can avoid it.
	- Bad:
		var thing: int = 0:
			set(v):
				thing = v
				$MyThing.text = str(v)
	
	- Good:
		@onready var label: Label = $MyThing
		
		var thing: int = 0:
			set(v):
				thing = v
				label.text = str(v)
