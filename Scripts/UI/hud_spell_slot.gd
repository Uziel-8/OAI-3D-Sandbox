class_name HudSpellSlot
extends Control
## One socket on the HUD's spell bar: the key that casts it, the spell's glyph
## and colour, its mana cost, and a cooldown sweep that drains as the spell
## recovers.
##
## Built entirely in code with no .tscn, like the HUD's quest-tracker block --
## deliberate, both because the bar's contents are driven by
## SpellCaster.LOADOUT_ACTIONS rather than hand-placed, and because it keeps the
## stale-`parent=` NodePath hazard documented in CLAUDE.md out of hud.tscn.
##
## Display-only: every node here ignores the mouse so the bar can never eat a
## casting click.

const SIZE := Vector2(54, 54)

## Which input action this socket shows. Set once by the HUD when the bar is built.
var action: String = ""

var _spell: Spell = null
var _definition: SpellDefinition = null

var _style: StyleBoxFlat
var _bg: Panel
var _glyph: Label
var _veil: ColorRect
var _timer: Label
var _key: Label
var _cost: Label


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.07, 0.065, 0.08, 0.72)
	_style.set_corner_radius_all(6)
	_style.set_border_width_all(2)
	_style.border_color = Color(1, 1, 1, 0.12)

	_bg = Panel.new()
	_bg.add_theme_stylebox_override("panel", _style)
	_add_full_rect(_bg)

	_glyph = _make_label(20, Color(0.95, 0.93, 0.9))
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_add_full_rect(_glyph)

	# The sweep: covers the whole face the instant a spell is cast and drains
	# upward, so the icon is uncovered exactly as the spell becomes castable.
	_veil = ColorRect.new()
	_veil.color = Color(0.02, 0.02, 0.03, 0.72)
	_veil.visible = false
	_add_full_rect(_veil)

	_timer = _make_label(15, Color(0.98, 0.9, 0.66))
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer.visible = false
	_add_full_rect(_timer)

	_key = _make_label(10, Color(0.95, 0.86, 0.6))
	_key.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_key.offset_left = 5.0
	_key.offset_top = 2.0
	add_child(_key)

	_cost = _make_label(10, Color(0.55, 0.72, 0.98))
	_cost.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cost.offset_left = -30.0
	_cost.offset_top = -17.0
	_cost.offset_right = -5.0
	_cost.offset_bottom = -3.0
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_cost)

	_apply_spell()


func _add_full_rect(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The key/button that fires this slot, e.g. "LMB" or "Q".
func set_key_text(text: String) -> void:
	if _key:
		_key.text = text


## Points the socket at the live Spell node bound to its action (null = empty
## slot). `definition` is the spellbook entry it was instanced from, used purely
## for the glyph and colour.
func set_spell(spell: Spell, definition: SpellDefinition) -> void:
	_spell = spell
	_definition = definition
	if is_node_ready():
		_apply_spell()


func _apply_spell() -> void:
	var has_spell := _spell != null and is_instance_valid(_spell)
	if has_spell:
		_glyph.text = _definition.icon_text() if _definition else "?"
		_style.border_color = _definition.icon_color if _definition else Color(0.7, 0.7, 0.75)
		_cost.text = "%d" % roundi(_spell.mana_cost) if _spell.mana_cost > 0.0 else ""
	else:
		_glyph.text = ""
		_cost.text = ""
		_style.border_color = Color(1, 1, 1, 0.1)
		_veil.visible = false
		_timer.visible = false
	modulate.a = 1.0 if has_spell else 0.55


## Per-frame refresh, driven by the HUD. `mana` is the player's current pool, so
## a spell you can't currently pay for reads as unavailable the same way one on
## cooldown does.
func refresh(mana: float) -> void:
	if _spell == null or not is_instance_valid(_spell):
		return

	var ratio := _spell.cooldown_ratio()
	if ratio > 0.0:
		_veil.visible = true
		_veil.anchor_bottom = ratio
		var left := _spell.cooldown_remaining()
		_timer.text = "%.1f" % left if left < 1.0 else "%d" % ceili(left)
		_timer.visible = true
	else:
		_veil.visible = false
		_timer.visible = false

	var affordable := _spell.mana_cost <= 0.0 or mana >= _spell.mana_cost
	_glyph.modulate = Color(1, 1, 1) if affordable else Color(1, 0.45, 0.45, 0.75)
	_cost.add_theme_color_override("font_color",
		Color(0.55, 0.72, 0.98) if affordable else Color(1, 0.45, 0.45))
