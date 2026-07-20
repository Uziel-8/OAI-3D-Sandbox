extends Node
class_name SkillTreeSystem
## Owns which skill-tree nodes the player has unlocked, and the rules for
## unlocking them. Registered as the `SkillSystem` autoload AFTER PlayerProgression
## (it spends that system's skill_points), so it persists across scene reloads and
## any system can query it. The schools/nodes themselves are data (MockSkillTrees);
## this holds only the unlocked SET and the logic.
##
## Effect consumption:
##   UNLOCK_SPELL -> unlocked_spell_ids(), read by the spellbook to gate what's equippable (FULLY WIRED)
##   PASSIVE      -> passive_total(key)  (scaffolding: summed and queryable, no consumers yet)
##   UPGRADE      -> has_upgrade(id)     (scaffolding: queryable, no Spell reads it yet)

signal skill_unlocked(node_id: String)
## Fired on any change to the unlocked set (unlock or reset) so UI can rebuild.
signal tree_changed

var _schools: Array[SkillSchool] = []
var _nodes_by_id: Dictionary = {}      # node id -> SkillNode
var _unlocked: Dictionary = {}         # node id -> true (used as a set)


func _ready() -> void:
	# Cache the school/node data once so the tree view and this system share the
	# same SkillNode object identities (MockSkillTrees builds fresh instances).
	_schools = MockSkillTrees.schools()
	for school in _schools:
		for node in school.nodes:
			_nodes_by_id[node.id] = node


# --- Data access -------------------------------------------------------------

func get_schools() -> Array[SkillSchool]:
	return _schools

func get_node_def(node_id: String) -> SkillNode:
	return _nodes_by_id.get(node_id, null)


# --- Query -------------------------------------------------------------------

func is_unlocked(node_id: String) -> bool:
	return _unlocked.has(node_id)

## True if every prerequisite of the node is already unlocked (ignores cost).
func prerequisites_met(node: SkillNode) -> bool:
	for req in node.prerequisites:
		if not _unlocked.has(req):
			return false
	return true

## True if the node can be unlocked right now: not already owned, prerequisites
## met, and the player can afford it.
func can_unlock(node: SkillNode) -> bool:
	if node == null or _unlocked.has(node.id):
		return false
	if not prerequisites_met(node):
		return false
	return _available_points() >= node.cost


# --- Mutation ----------------------------------------------------------------

## Attempts to unlock node_id, spending skill points. Returns true on success.
func unlock(node_id: String) -> bool:
	var node: SkillNode = _nodes_by_id.get(node_id, null)
	if not can_unlock(node):
		return false
	var prog := _progression()
	if prog == null or not prog.spend_skill_point(node.cost):
		return false
	_unlocked[node_id] = true
	skill_unlocked.emit(node_id)
	tree_changed.emit()
	return true

## Refunds all spent points and clears the unlocked set (respec). Scaffolding for
## a future respec UI -- no screen calls this yet.
func reset() -> void:
	var refund := 0
	for node_id in _unlocked:
		var node: SkillNode = _nodes_by_id.get(node_id, null)
		if node:
			refund += node.cost
	_unlocked.clear()
	var prog := _progression()
	if prog and refund > 0:
		prog.grant_skill_points(refund)
	tree_changed.emit()


# --- Effect readouts ---------------------------------------------------------

## SpellDefinition ids the player has unlocked via UNLOCK_SPELL nodes. The
## spellbook filters its palette by this so only unlocked spells are equippable.
func unlocked_spell_ids() -> Array[String]:
	var ids: Array[String] = []
	for node_id in _unlocked:
		var node: SkillNode = _nodes_by_id.get(node_id, null)
		if node and node.effect == SkillNode.Effect.UNLOCK_SPELL and node.unlock_spell_id != "":
			ids.append(node.unlock_spell_id)
	return ids

## Summed additive value of a passive-bonus key across unlocked PASSIVE nodes.
## Scaffolding: nothing reads this yet -- consumers (ProjectileSpell, PlayerState…)
## can start calling it once passives are fleshed out.
func passive_total(key: String) -> float:
	var total := 0.0
	for node_id in _unlocked:
		var node: SkillNode = _nodes_by_id.get(node_id, null)
		if node and node.effect == SkillNode.Effect.PASSIVE:
			total += float(node.passive_bonuses.get(key, 0.0))
	return total

## Whether an unlocked UPGRADE node grants the given tag. Scaffolding: no Spell
## script checks this yet.
func has_upgrade(upgrade_id: String) -> bool:
	for node_id in _unlocked:
		var node: SkillNode = _nodes_by_id.get(node_id, null)
		if node and node.effect == SkillNode.Effect.UPGRADE and node.upgrade_id == upgrade_id:
			return true
	return false


# --- Internals ---------------------------------------------------------------

func _progression() -> ProgressionSystem:
	return get_node_or_null("/root/PlayerProgression") as ProgressionSystem

func _available_points() -> int:
	var prog := _progression()
	return prog.skill_points if prog else 0
