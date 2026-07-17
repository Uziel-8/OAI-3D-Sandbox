# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Godot 4.7 (Forward+ renderer, Jolt physics, D3D12 on Windows) third-person immersive-sim/RPG sandbox, currently greenfield/prototype stage. No README, no test suite, no CI — this file is the only project-level documentation.

## Commands

Godot executable (Steam install, not on PATH):
```
"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
```

Check the whole project for script/scene parse errors (fast, no window):
```
godot.exe --headless --path <project> --check-only --quit
```
Note: on a machine/checkout where `.godot/` hasn't been generated yet (e.g. after adding new `class_name` scripts), `--check-only` alone can report false "Could not find type X" errors because the global class cache isn't built. Fix by first running:
```
godot.exe --headless --editor --path <project> --quit-after 20
```
then re-run `--check-only`.

Run the actual game (not the editor) directly into a scene:
```
godot.exe --path <project> res://Scenes/level.tscn
```
Running `godot.exe --path <project>` with no scene argument opens the **editor**, not the game — the window title says "... - Godot Engine" when that happens.

There is no build step, linter, or automated test suite in this project.

## Architecture

### Plugin-style ability system (`Scripts/Magic/`)
`SpellCaster` (a `Node` under the player's `Camera3D`) iterates its own `Spell`-derived children every physics frame and drives each through `start_cast()` → `hold_cast(delta)` (repeatedly while held) → `end_cast()`, keyed off each spell's own `trigger_action` input action. Adding a new ability means adding a new `Spell` subclass as a child scene under the camera — `SpellCaster` itself never needs to change. `instant` spells (`@export var instant`) skip the hold/release phase and fire once on press.

Spells affect the world via **duck typing, not shared base classes**: e.g. `TelekinesisPushSpell`/`TelekinesisGrabSpell` call `apply_impulse(impulse, position)` on anything that has that method (checked via `has_method`), and target the `"grabbable"` group for grab specifically. `SpiderWalker` implements `apply_impulse()` itself (folding the impulse into `velocity` since it's a `CharacterBody3D`, not a `RigidBody3D`) purely so spells can affect it without knowing its concrete type. **Follow this convention** for anything new that should be pushable/grabbable — implement `apply_impulse()`, don't add a shared interface class.

### Enemies (`Enemies/`)
`SpiderWalker` is fully self-contained and procedural: drop the scene anywhere in a level with zero required configuration and it wanders on its own (centered on wherever it was placed), optionally chasing the `"player"` group if `chase_player` is set. All leg motion is IK-driven at runtime by `SpiderGait`/`SpiderSkeletonBuilder` (`spider_gait.gd`, `spider_skeleton_builder.gd`) — there are no animation clips. There is currently no health/damage/death/loot-drop system anywhere in the project; `apply_impulse()` knockback is the only reaction enemies have to being hit.

### Player (`Scenes/brackeys-proto-controller-main/`)
The player is the unmodified third-party Brackeys `ProtoController` (`CharacterBody3D`, group `"player"`), configured via exported input-action-name strings rather than hardcoded actions. It self-manages mouse capture (`capture_mouse()`/`release_mouse()`) — left-click captures, Escape releases — polled every `_unhandled_input`, not event-filtered. Anything that opens a full-screen UI must consume input at the `Control` layer (`mouse_filter = STOP` on a full-rect backdrop) so clicks don't fall through to `_unhandled_input` and re-trigger capture.

### UI (`Scripts/UI/`, `Scenes/UI/`)
The inventory/character screen is the first UI in the project and sets the conventions for future screens:
- Registered as an **autoload singleton** (`InventoryUI` in `project.godot`) rather than a node manually placed in every level, so it's available everywhere and isn't tied to `level.tscn`.
- Toggled by the `inventory` input action (Tab, already mapped in `project.godot` before this system existed). Opening sets `get_tree().paused = true` and `Input.mouse_mode = VISIBLE`; the screen node and everything under it must have `process_mode = PROCESS_MODE_ALWAYS` (set on the root `CanvasLayer`) or it stops receiving input the moment the tree pauses.
- `InventorySlot` (`Scenes/UI/inventory_slot.tscn`) is a single dual-purpose component used for both backpack grid cells and paper-doll equipment sockets (`is_equipment_slot` + `accepted_equip_slot` toggle the behavior) — not two separate slot classes. It owns its own drag-and-drop (`_get_drag_data`/`_can_drop_data`/`_drop_data`) and double-click quick-transfer, and notifies the screen via `get_tree().get_first_node_in_group("inventory_screen")` rather than a direct reference.
- `InventoryItem` (`Scripts/UI/item.gd`) is a plain `Resource` data shape with no backing item/save system yet. `MockItemDatabase` (`Scripts/UI/mock_item_database.gd`) is placeholder demo data standing in for that system — replace it, don't extend it, once real loot/persistence exists.
- Shared look-and-feel lives in one `Theme` resource (`Scenes/UI/inventory_theme.tres`, dark panels + brass borders) applied at the screen root so new UI should pull from it rather than re-declaring styleboxes per-scene. This file gets hand-edited/re-saved by the Godot editor directly (not just through Claude), so re-read it before assuming its contents rather than trusting an earlier diff.

### Level scene (`Scenes/level.tscn`)
Mostly hundreds of hand-placed `Floor`/`Wall` tile instances plus a few set-piece nodes (`ProtoController`, `SpiderWalker`, pirate ship, barrels). When editing this file directly as text, be careful with `unique_id` node attributes and don't try to read/edit the whole floor-tile block — it's bulk, not structure.

### Input map (`project.godot`)
Actions are pre-declared even when unused by any script yet (e.g. `interact` on F was unused until recently, `inventory` on Tab similarly) — check `[input]` in `project.godot` before assuming an action needs to be created for a new feature.

### Magic loadout system (Fireball/Ice Bolt, spellbook tab)
`SpellCaster.equip_spell(trigger_action, spell_scene)` / `unequip_slot(trigger_action)` dynamically add/remove a `Spell`-derived scene as a child so a hotbar slot's binding can change at runtime — used by the inventory's Spellbook tab. Every equippable ability (`TelekinesisGrab/Push`, `FireballSpell`, `IceboltSpell`) is authored as its own standalone `.tscn` under `Scripts/Magic/` (not inline nodes in `proto_controller.tscn`) specifically so it can be `instance=`'d both as the default loadout in `proto_controller.tscn` *and* dynamically via `equip_spell()`. `ProjectileSpell`/`Projectile` are generic (spawn-and-fly-and-impact) scripts parametrized per spell via scene config (mesh/particle colors, speed, impact force) rather than duplicated per spell — adding a third projectile spell means authoring a new `Projectile` scene, not new code. `SpellDefinition`/`MockSpellbook` mirror the `InventoryItem`/`MockItemDatabase` mock-data pattern.

### Godot 4.7.1 gotcha: `unique_name_in_owner` on scene-instance nodes
Setting `unique_name_in_owner = true` as a property override on a node that is itself a `PackedScene` instance (e.g. an `InventorySlot`/`SpellSlot` placed via `instance=ExtResource(...)`) reproducibly corrupts `PackedScene::instantiate()` in this Godot build: every node declared after the first such instance silently fails to resolve its parent path and gets flattened onto the scene root (`WARNING: Parent path '...' has vanished when instantiating`), which then cascades into `%Name` lookups failing entirely. Confirmed via isolated minimal repros — not about node depth, naming, TabContainer, or resource UIDs. **Only apply `unique_name_in_owner` to plain built-in node types.** For instanced nodes you need a stable reference to, use an explicit `$relative/path/To/Node` in the controlling script instead of `%UniqueName` (see the `_CHAR_PATH`/`_SPELL_PATH` constants in `inventory_screen.gd`).

Separately: don't hand-write `uid="uid://..."` attributes when authoring new `.tscn`/`.tres` files by hand (outside the editor) — a fabricated UID isn't registered anywhere and risks colliding with one Godot generates for something else during a full reimport. Omit `uid=` and reference by `path=` only; Godot fills in a real UID the next time the file is saved through the actual editor.
