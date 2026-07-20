class_name SkillTreeView
extends Control
## Renders ONE school's skill tree: a SkillNodeButton per node positioned by its
## grid_position, with connector lines drawn (in _draw, so they sit behind the
## buttons) between each node and its prerequisites. Owns unlock-on-click and
## re-renders itself on SkillSystem.tree_changed. Emits hover signals so the
## screen can drive the shared tooltip.
##
## Adding schools/nodes needs no changes here -- everything derives from the data
## passed to display_school().

signal node_hovered(node: SkillNode, status: String)
signal node_unhovered

const NodeButtonScene := preload("res://Scenes/UI/skill_node_button.tscn")

const NODE_SIZE := 80.0
const H_SPACING := 150.0
const V_SPACING := 130.0
const MARGIN := Vector2(40, 30)

var _school: SkillSchool
var _buttons: Array[SkillNodeButton] = []
var _hovered: SkillNodeButton = null

func _ready() -> void:
	var skills := _skills()
	if skills:
		skills.tree_changed.connect(_refresh)

func display_school(school: SkillSchool) -> void:
	_school = school
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_hovered = null
	if school == null:
		queue_redraw()
		return

	var max_col := 0
	var max_row := 0
	for node in school.nodes:
		var button := NodeButtonScene.instantiate() as SkillNodeButton
		add_child(button)
		button.position = _node_pos(node)
		button.setup(node, _state_for(node))
		button.hovered.connect(_on_button_hovered)
		button.unhovered.connect(_on_button_unhovered)
		button.clicked.connect(_on_button_clicked)
		_buttons.append(button)
		max_col = maxi(max_col, node.grid_position.x)
		max_row = maxi(max_row, node.grid_position.y)

	custom_minimum_size = Vector2(
		2.0 * MARGIN.x + max_col * H_SPACING + NODE_SIZE,
		2.0 * MARGIN.y + max_row * V_SPACING + NODE_SIZE)
	queue_redraw()

## Recomputes every button's state + redraws the lines. Called on tree_changed.
func _refresh() -> void:
	for button in _buttons:
		button.setup(button.node, _state_for(button.node))
	queue_redraw()
	# Keep the tooltip in step if the player is still hovering a node they just changed.
	if _hovered and is_instance_valid(_hovered):
		node_hovered.emit(_hovered.node, _status_for(_hovered.node))

func _draw() -> void:
	if _school == null:
		return
	var skills := _skills()
	for node in _school.nodes:
		var to_center := _node_pos(node) + Vector2(NODE_SIZE, NODE_SIZE) * 0.5
		for req_id in node.prerequisites:
			var req := _school.find_node(req_id)
			if req == null:
				continue
			var from_center := _node_pos(req) + Vector2(NODE_SIZE, NODE_SIZE) * 0.5
			draw_line(from_center, to_center, _edge_color(node, req_id, skills), 3.0, true)

func _edge_color(node: SkillNode, req_id: String, skills: SkillTreeSystem) -> Color:
	if skills == null:
		return Color(1, 1, 1, 0.12)
	if skills.is_unlocked(node.id):
		return node.icon_color                       # path taken
	if skills.is_unlocked(req_id):
		return Color(node.icon_color, 0.55)          # prereq met, node purchasable
	return Color(1, 1, 1, 0.1)                        # dormant

# --- Node state / status -----------------------------------------------------

func _node_pos(node: SkillNode) -> Vector2:
	return MARGIN + Vector2(node.grid_position.x * H_SPACING, node.grid_position.y * V_SPACING)

func _state_for(node: SkillNode) -> SkillNodeButton.State:
	var skills := _skills()
	if skills == null:
		return SkillNodeButton.State.LOCKED
	if skills.is_unlocked(node.id):
		return SkillNodeButton.State.UNLOCKED
	if not skills.prerequisites_met(node):
		return SkillNodeButton.State.LOCKED
	if skills.can_unlock(node):
		return SkillNodeButton.State.AVAILABLE
	return SkillNodeButton.State.UNAFFORDABLE

func _status_for(node: SkillNode) -> String:
	var skills := _skills()
	if skills == null:
		return ""
	if skills.is_unlocked(node.id):
		return "Unlocked"
	var pts := "%d point%s" % [node.cost, "" if node.cost == 1 else "s"]
	if not skills.prerequisites_met(node):
		var missing: Array[String] = []
		for req_id in node.prerequisites:
			if not skills.is_unlocked(req_id):
				var req := skills.get_node_def(req_id)
				missing.append(req.display_name if req else req_id)
		return "Locked — requires " + ", ".join(missing)
	if skills.can_unlock(node):
		return "Click to unlock  (%s)" % pts
	return "Costs %s — not enough" % pts

# --- Signals -----------------------------------------------------------------

func _on_button_hovered(button: SkillNodeButton) -> void:
	_hovered = button
	node_hovered.emit(button.node, _status_for(button.node))

func _on_button_unhovered() -> void:
	_hovered = null
	node_unhovered.emit()

func _on_button_clicked(button: SkillNodeButton) -> void:
	var skills := _skills()
	if skills:
		skills.unlock(button.node.id)  # tree_changed -> _refresh handles the redraw

func _skills() -> SkillTreeSystem:
	return get_node_or_null("/root/SkillSystem") as SkillTreeSystem
