class_name SkillNodeButton
extends PanelContainer
## One clickable node on a SkillTreeView canvas. Data-driven from a SkillNode; the
## owning SkillTreeView computes the display State (it knows the unlock set + point
## balance) and passes it in via setup(), so this button stays decoupled from
## SkillSystem. Emits hover (for the shared tooltip) and click (to request unlock).

signal hovered(button: SkillNodeButton)
signal unhovered
signal clicked(button: SkillNodeButton)

enum State {
	UNLOCKED,      ## already owned
	AVAILABLE,     ## prerequisites met AND affordable -- click to buy
	UNAFFORDABLE,  ## prerequisites met but not enough skill points
	LOCKED,        ## prerequisites not yet met
}

var node: SkillNode
var state: State = State.LOCKED

@onready var _icon_bg: Panel = %IconBg
@onready var _glyph: Label = %Glyph
@onready var _cost: Label = %Cost

var _style: StyleBoxFlat
var _hovering := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.12, 0.11, 0.13, 1.0)
	_style.set_corner_radius_all(8)
	_style.set_border_width_all(2)
	_style.border_color = Color(1, 1, 1, 0.12)
	add_theme_stylebox_override("panel", _style)
	_render()

func setup(skill_node: SkillNode, node_state: State) -> void:
	node = skill_node
	state = node_state
	if is_node_ready():
		_render()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func _on_mouse_entered() -> void:
	_hovering = true
	_apply_hover()
	hovered.emit(self)

func _on_mouse_exited() -> void:
	_hovering = false
	_apply_hover()
	unhovered.emit()

func _render() -> void:
	if node == null:
		return
	_glyph.text = node.icon_text()
	_cost.text = str(node.cost)
	var accent := node.icon_color
	match state:
		State.UNLOCKED:
			_icon_bg.self_modulate = accent
			_glyph.add_theme_color_override("font_color", Color(0.05, 0.05, 0.06))
			_cost.visible = false
			_style.border_color = accent
			modulate = Color(1, 1, 1, 1)
		State.AVAILABLE:
			_icon_bg.self_modulate = accent.darkened(0.35)
			_glyph.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86))
			_cost.visible = true
			# brass = actionable, matching the theme's affordance colour
			_style.border_color = Color(0.95, 0.86, 0.6)
			modulate = Color(1, 1, 1, 1)
		State.UNAFFORDABLE:
			_icon_bg.self_modulate = accent.darkened(0.55)
			_glyph.add_theme_color_override("font_color", Color(0.8, 0.78, 0.74))
			_cost.visible = true
			_style.border_color = Color(1, 1, 1, 0.2)
			modulate = Color(1, 1, 1, 1)
		State.LOCKED:
			_icon_bg.self_modulate = accent.darkened(0.7)
			_glyph.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			_cost.visible = true
			_style.border_color = Color(1, 1, 1, 0.1)
			modulate = Color(0.6, 0.6, 0.6, 1)
	_apply_hover()

func _apply_hover() -> void:
	_style.set_border_width_all(3 if _hovering else 2)
	_style.bg_color = Color(0.17, 0.16, 0.18, 1.0) if _hovering else Color(0.12, 0.11, 0.13, 1.0)
