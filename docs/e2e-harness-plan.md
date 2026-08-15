# Godot MMORPG E2E Harness Plan

## Summary

Build an end-to-end testing harness that starts the real backend pieces, runs a
headless Godot test client, drives the real network protocols, and asserts on
observed outcomes. The harness should skip UI screens, but it should not skip
the application flows that matter: orchestrator login, character selection, zone
redirect, ENet zone connection, zone login, and gameplay messages.

The E2E layer must be a driver and observer. It may call existing APIs and
inspect existing nodes, but it must not duplicate gameplay or business logic.
For example, it can request that an item be equipped and then wait for replicated
equipment state, but it must not reimplement equip validation rules to predict
the result.

## Goals

- Spin up a fresh orchestrator and one or more headless zone servers for each
  E2E suite.
- Run a headless Godot E2E client that uses the same protocol encoders,
  decoders, ENet APIs, and client-side routing code as the real client.
- Provide a reusable "get in game" fixture so tests do not repeat login and
  zone-entry setup.
- Make test cases easy to write as gameplay-level interactions:
  equip item, unequip item, equip multiple items, move, observe snapshots, and
  eventually use multiple clients.
- Keep assertions grounded in real observed system behavior: server responses,
  replicated client state, game events, node state, and optional structured test
  events.
- Produce useful artifacts for failures: process logs, structured test events,
  exit statuses, and the final test result.

## Non-Goals

- Do not drive the UI layer for v1. Screen-level UI tests can be added later as
  a separate layer.
- Do not reimplement gameplay rules in the harness.
- Do not use raw prose logs as the primary assertion mechanism.
- Do not make parallel E2E execution a v1 requirement. Sequential suites with
  fresh processes are acceptable.

## Architecture

### Process Runner

Add an external E2E runner that owns process lifecycle for a suite:

1. Allocate unique ports for orchestrator, zone servers, and client-facing
   endpoints.
2. Create a per-run artifact directory such as `logs/e2e/<run-id>/`.
3. Start the orchestrator.
4. Wait for orchestrator health/readiness.
5. Start one or more headless Godot zone servers.
6. Wait until expected zones are registered with the orchestrator.
7. Start the headless Godot E2E client scene or script.
8. Wait for a structured test result.
9. Stop all child processes, even on failure or timeout.
10. Return a non-zero exit code when any E2E test fails.

The runner can reuse the existing launch script patterns, but it should be
separate from the interactive `make servers` flow because E2E needs random
ports, strict timeouts, isolated logs, and deterministic cleanup.

### Headless Godot E2E Client

The E2E client should be a Godot-side test driver. This avoids reimplementing
the ENet/binary wire protocol in Go, Python, or shell code.

The test client should reuse existing production code wherever practical:

- `OrchestratorAPI` for WebSocket login and character selection.
- `GameServerAPI` for ENet connection and gameplay packets.
- Protocol message classes for encoding and decoding packets.
- Client protocol routers and game event sources for receiving replicated
  outcomes.
- Existing node state such as `Player`, `Equipment`, and entity state when the
  test needs to observe final client-side state.

The E2E client should not instantiate UI screens just to get into the world.
Instead, extract or add a UI-independent session bootstrapper that performs the
same network sequence currently coordinated by the UI flow.

### Session Bootstrapper

Create a reusable E2E session helper responsible for the full "get in game"
workflow:

1. Connect to the orchestrator WebSocket.
2. Send login request for a test username.
3. Receive available characters.
4. Select a character.
5. Receive zone redirect.
6. Connect to the target zone over ENet.
7. Send zone login with character id and transfer token.
8. Wait for character loaded / controlled entity assignment.
9. Return a session object with API access, observed ids, and event/state
   observation helpers.

Example shape:

```gdscript
var session := await E2ESession.start({
    "username": "e2e_equipment",
    "zone_id": "mvp",
})
```

The helper should own boring orchestration, timeout handling, and diagnostics.
It should not own gameplay decisions.

### Dedicated Test Zone And Fixtures

Add a deterministic E2E zone or E2E zone mode. It should be small, predictable,
and cheap to run headless.

Recommended properties:

- Stable spawn point.
- Known zone id, such as `e2e` or a test-mode `mvp`.
- Deterministic tick rate.
- Known starter character state.
- Known equipment/inventory fixtures.
- Minimal world complexity.
- Optional fixture reset on process start.

The fixture setup can be test-only, but gameplay requests should still travel
through the same network and server handlers that production gameplay uses.

## E2E API Boundary

The harness API is allowed to drive interactions:

```gdscript
var request_id := session.request_equip_item(slot_id, item_instance_id, template_path)
var result_code := await session.wait_for_action_result(request_id)
await session.wait_for_equipped(slot_id, item_instance_id)
```

The harness API is allowed to observe existing state:

```gdscript
var player := session.local_player()
assert_true(player.equipment.has_equipped_slot(slot_id))
assert_eq(player.global_position.round(), expected_area)
```

The harness API must not duplicate game logic:

```gdscript
# Do not do this in E2E helpers.
if item.template.equippable.slots.has(slot_id):
    expected_revision += 1
```

Good helper names should describe driving and observing:

- `login_as`
- `enter_default_zone`
- `request_equip_item`
- `request_unequip_slot`
- `wait_for_action_result`
- `wait_for_equipped`
- `send_movement_input`
- `wait_for_snapshot`
- `local_player`

Avoid helper names that imply duplicated rules:

- `can_equip`
- `calculate_expected_stats`
- `resolve_inventory_delta`
- `simulate_movement`
- `predict_equipment_revision`

For negative tests, the harness should set up the scenario, send the real
request, and assert the real rejection:

```gdscript
var request_id := session.request_equip_item(invalid_slot, item_id, template_path)
var result_code := await session.wait_for_action_result(request_id)
assert_eq(result_code, EntityEquipmentActionResultMsg.RESULT_INVALID_SLOT)
```

The rejection code comes from the server response. The harness does not compute
whether the action should have been rejected.

## Observability

Use a hierarchy of observability sources:

1. Primary: packets, events, and replicated state observed by the E2E client.
2. Secondary: structured server-side test events, emitted only in test mode.
3. Debug: full process logs from orchestrator, zones, and test client.

Do not make raw prose log messages the primary oracle. They are too brittle.
If server-side instrumentation is needed, emit stable JSONL events such as:

```json
{"type":"player_loaded","peer_id":1,"entity_id":1001,"character_id":1}
{"type":"equipment_action","request_id":3,"result":"ok","revision":2}
```

These events should describe observed server facts, not separate test-only
business logic.

## Initial Milestones

### Milestone 1: Boot And Enter World

Implement the smallest useful E2E path:

- `make e2e` target or equivalent script entrypoint.
- Fresh orchestrator process.
- One fresh headless Godot zone process.
- One headless Godot E2E client process.
- Login as a test user.
- Select default character.
- Receive zone redirect.
- Connect to zone.
- Send zone login.
- Observe character loaded.
- Emit structured pass/fail result.
- Collect artifacts and clean up processes.

This milestone proves process lifecycle, networking, readiness waits, and the
reusable session bootstrapper.

### Milestone 2: Equipment Flow

Add gameplay-level equipment tests:

- Equip one item and observe equipment action result.
- Observe replicated equipment state on the local player.
- Unequip the item and observe state removal.
- Equip multiple items sequentially.
- Send an invalid equipment request and assert the real server rejection.

Assertions should use equipment responses, replicated equipment messages,
game events, or existing `Equipment` state.

### Milestone 3: Movement Flow

Add movement tests:

- Send movement input frames through the real client API.
- Observe authoritative movement snapshots.
- Assert that the observed player position changes as expected.
- Keep the harness from implementing its own movement simulation.

The test may assert broad outcome ranges or snapshot properties instead of
calculating exact physics results independently.

### Milestone 4: Multi-Client Flow

Add multi-client coverage after single-client flows are stable:

- Start two E2E sessions against the same zone.
- Move one client.
- Assert the other client observes the remote entity update.
- Exercise equipment changes and entity lifecycle replication across clients.

## Failure Handling

Every wait should have a named timeout and diagnostic output. Failures should
include:

- The failed E2E step name.
- The timeout or error reason.
- Relevant observed ids, such as character id, entity id, peer id, request id,
  and zone id.
- Paths to logs and structured event files.

The process runner should always tear down children. A failed child process,
timeout, or test assertion should make the overall command fail.

## Acceptance Criteria

The first implemented version is acceptable when:

- A single command can run the E2E suite from a clean checkout with Godot and Go
  available.
- Each suite starts fresh processes and stops them reliably.
- The E2E client enters the world without using UI screens.
- Tests drive real orchestrator and ENet messages.
- Test helpers do not duplicate gameplay rules.
- Failures produce enough artifacts to diagnose which process or step failed.
- Existing GUT unit tests remain independent from E2E tests.

## Open Implementation Choices

These choices should be made during implementation, but they should preserve
the boundaries in this document:

- Whether the runner is shell-first, Go-first, or a thin Make target over a
  script.
- Whether E2E test cases use GUT as the assertion runner or a small custom
  headless Godot test runner.
- Whether structured server-side test events are needed for milestone 1 or can
  wait until equipment/movement tests.
- Whether the dedicated test zone is a new zone scene or a test fixture mode for
  an existing zone.
