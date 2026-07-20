extends CanvasLayer
## Always-on gameplay overlay: health / mana / stamina / XP bars, gold counter,
## mission objective, and the level-up toast. Registered as the `HUD` autoload
## so it exists in every scene. Binds to three sources: the player's
## DamageReceiver (group "player_health", re-acquired on scene reload), the
## PlayerProgression autoload (XP/level + level-up toast), and the PlayerState
## autoload (gold/mana/stamina). Display-only -- every node ignores mouse input
## so it never intercepts casting clicks.

@onready var _root: Control = $Root
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _mana_bar: ProgressBar = %ManaBar
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _xp_bar: ProgressBar = %XPBar
@onready var _level_label: Label = %LevelLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _objective_title: Label = %ObjectiveTitle
@onready var _objective_text: Label = %ObjectiveText
@onready var _toast: Label = %LevelUpToast
@onready var _interact_prompt: Label = %InteractPrompt

var _health_receiver: DamageReceiver
var _toast_tween: Tween


func _ready() -> void:
	add_to_group("hud")
	_toast.modulate.a = 0.0

	var prog := get_node_or_null("/root/PlayerProgression")
	if prog:
		prog.experience_gained.connect(_on_xp_changed)
		prog.leveled_up.connect(_on_leveled_up)
		_on_xp_changed(prog.current_xp, prog.xp_to_next(), prog.level)

	var state := get_node_or_null("/root/PlayerState")
	if state:
		state.gold_changed.connect(_on_gold_changed)
		state.mana_changed.connect(_on_mana_changed)
		state.stamina_changed.connect(_on_stamina_changed)
		_on_gold_changed(state.gold)
		_on_mana_changed(state.mana, state.max_mana)
		_on_stamina_changed(state.stamina, state.max_stamina)

	# Health lives on the player body, which is recreated on the death-reload,
	# so (re)bind whenever a player_health receiver enters the tree.
	get_tree().node_added.connect(_on_node_added)
	_bind_player_health.call_deferred()

	# Neutral default; each level's LevelObjectives node sets its own objective.
	set_objective("No Objective", "Your current objective will appear here.")
	set_interact_prompt("")


## Shows/hides the centred interaction prompt (e.g. "[F]  Speak"). Driven by the
## player's PlayerInteractor; empty text hides it.
func set_interact_prompt(text: String) -> void:
	_interact_prompt.text = text
	_interact_prompt.visible = text != ""


func _on_node_added(node: Node) -> void:
	if node.is_in_group("player_health"):
		_bind_player_health()


func _bind_player_health() -> void:
	var receiver := get_tree().get_first_node_in_group("player_health") as DamageReceiver
	if receiver == null or receiver == _health_receiver:
		return
	_health_receiver = receiver
	if not receiver.health_changed.is_connected(_on_health_changed):
		receiver.health_changed.connect(_on_health_changed)
	_on_health_changed(receiver.health, receiver.max_health)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_mana_changed(current: float, maximum: float) -> void:
	_mana_bar.max_value = maximum
	_mana_bar.value = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current


func _on_gold_changed(gold: int) -> void:
	_gold_label.text = str(gold)


func _on_xp_changed(current_xp: float, xp_to_next: float, level: int) -> void:
	_xp_bar.max_value = xp_to_next
	_xp_bar.value = current_xp
	_level_label.text = "Lv %d" % level


func _on_leveled_up(new_level: int, _attribute_points: int, _skill_points: int) -> void:
	var prog := get_node_or_null("/root/PlayerProgression")
	if prog:
		_on_xp_changed(prog.current_xp, prog.xp_to_next(), prog.level)
		_show_toast("LEVEL UP!", "Level %d   •   +%d attribute, +%d skill points" % [
			new_level, prog.attribute_points_per_level, prog.skill_points_per_level])
	else:
		_show_toast("LEVEL UP!", "Level %d" % new_level)


func _show_toast(title: String, subtitle: String) -> void:
	_toast.text = "%s\n%s" % [title, subtitle]
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


## Sets the on-screen mission objective. Call this from a future quest/objective
## system to retask the player.
func set_objective(title: String, text: String) -> void:
	_objective_title.text = title
	_objective_text.text = text


## Toggled by the inventory/character screen so the HUD doesn't show behind its
## full-screen backdrop.
func set_hud_visible(shown: bool) -> void:
	_root.visible = shown
