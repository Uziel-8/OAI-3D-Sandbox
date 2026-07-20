extends Node
class_name ProgressionSystem
## Global player progression: experience, level, and unspent attribute/skill
## points. Registered as the `PlayerProgression` autoload, so any system can
## award XP with `PlayerProgression.add_experience(x)` and the character screen
## can bind to its signals. Being an autoload, it PERSISTS across scene reloads
## (e.g. the player-death reload), so progress isn't wiped on death.
##
## ATTRIBUTES ARE LIVE: this is also the single tuning home for what each stat
## does. Four dual-purpose attributes, flat linear scaling per point above
## BASELINE (10):
##   CON — max health & health regen        (applied to the player's DamageReceiver)
##   DEX — stamina regen                    (applied via PlayerState multiplier)
##         (casting speed reserved for DEX once a cooldown system exists)
##   INT — magic damage & max mana          (ProjectileSpell reads magic_damage_multiplier;
##   WIL — magic damage & mana regen         PlayerState reads mana bonuses/multipliers)
## Consumers either bind to the signals below or read the derived getters.
## Skill points remain a tracked currency for a future ability-unlock system.

signal experience_gained(current_xp: float, xp_to_next: float, level: int)
signal leveled_up(new_level: int, attribute_points: int, skill_points: int)
signal points_changed(attribute_points: int, skill_points: int)
signal attribute_changed(attribute: String, value: int)
## Fired whenever any derived stat may have changed (attribute spent). PlayerState
## listens to recompute mana/stamina; the player's DamageReceiver is pushed to
## directly (see _apply_attributes).
signal derived_stats_changed

## The allocatable attributes, in display order.
const ATTRIBUTES: Array[String] = ["CON", "DEX", "INT", "WIL"]
## Attribute value at which every derived bonus is zero/neutral.
const BASELINE := 10

@export var base_xp: float = 100.0
## XP needed for the next level = round(base_xp * level ^ curve_exponent).
@export var curve_exponent: float = 1.5
@export var attribute_points_per_level: int = 30
@export var skill_points_per_level: int = 1
## Skill points the player starts with. With spells fully gated behind the skill
## trees, this is what lets a fresh game unlock a root or two immediately; set to
## 0 for a hardcore start where nothing is castable until you level.
@export var starting_skill_points: int = 3

@export_group("Stat Scaling (per point above baseline)")
## Player health before CON: matches the receiver authored in proto_controller.tscn.
@export var base_max_health: float = 100.0
@export var hp_per_con: float = 8.0
@export var hp_regen_per_con: float = 0.2
@export var stamina_regen_pct_per_dex: float = 0.05
@export var magic_damage_pct_per_int: float = 0.03
@export var mana_per_int: float = 6.0
@export var magic_damage_pct_per_wil: float = 0.02
@export var mana_regen_pct_per_wil: float = 0.05

var level: int = 1
var current_xp: float = 0.0
var attribute_points: int = 0
var skill_points: int = 0
var attributes: Dictionary = {"CON": 10, "DEX": 10, "INT": 10, "WIL": 10}

var _player_receiver: DamageReceiver


func _ready() -> void:
	skill_points = starting_skill_points
	# The player body (and its DamageReceiver) is recreated on the death-reload,
	# so push CON-derived health onto it whenever one enters the tree.
	get_tree().node_added.connect(_on_node_added)


# --- Derived stats -----------------------------------------------------------

func _delta(attribute: String) -> int:
	return attributes.get(attribute, BASELINE) - BASELINE


func player_max_health() -> float:
	return base_max_health + hp_per_con * _delta("CON")


func player_health_regen() -> float:
	return maxf(hp_regen_per_con * _delta("CON"), 0.0)


func magic_damage_multiplier() -> float:
	return maxf(1.0 + magic_damage_pct_per_int * _delta("INT")
		+ magic_damage_pct_per_wil * _delta("WIL"), 0.1)


func bonus_max_mana() -> float:
	return mana_per_int * _delta("INT")


func mana_regen_multiplier() -> float:
	return maxf(1.0 + mana_regen_pct_per_wil * _delta("WIL"), 0.1)


func stamina_regen_multiplier() -> float:
	return maxf(1.0 + stamina_regen_pct_per_dex * _delta("DEX"), 0.1)


# --- XP / levelling ----------------------------------------------------------

## XP required to advance from the current level to the next.
func xp_to_next() -> float:
	return round(base_xp * pow(float(level), curve_exponent))


## Reusable award entry point -- call this from anywhere (enemy deaths now;
## quests, persuasion, exploration, the remove-the-foreman objective later).
func add_experience(amount: float) -> void:
	if amount <= 0.0:
		return
	current_xp += amount
	while current_xp >= xp_to_next():
		current_xp -= xp_to_next()
		_level_up()
	experience_gained.emit(current_xp, xp_to_next(), level)


func _level_up() -> void:
	level += 1
	attribute_points += attribute_points_per_level
	skill_points += skill_points_per_level
	_apply_level_up()
	leveled_up.emit(level, attribute_points, skill_points)
	points_changed.emit(attribute_points, skill_points)


## Spends one attribute point into the given attribute. Returns true on success.
func spend_attribute_point(attribute: String) -> bool:
	if attribute_points <= 0 or not attributes.has(attribute):
		return false
	attribute_points -= 1
	attributes[attribute] += 1
	_apply_attributes()
	attribute_changed.emit(attribute, attributes[attribute])
	points_changed.emit(attribute_points, skill_points)
	return true


## Spends skill points (the currency behind the magic skill trees). SkillSystem
## calls this when unlocking a node; kept here so skill_points stays single-sourced
## and the HUD/character-sheet readouts keep working. Returns true on success.
func spend_skill_point(amount: int = 1) -> bool:
	if amount <= 0 or skill_points < amount:
		return false
	skill_points -= amount
	points_changed.emit(attribute_points, skill_points)
	return true


## Grants skill points from any source (respec refunds now; quests/rewards later).
func grant_skill_points(amount: int) -> void:
	if amount <= 0:
		return
	skill_points += amount
	points_changed.emit(attribute_points, skill_points)


## Per-level side effects beyond granting points. Kept minimal deliberately:
## power comes from spending points, not the level number itself.
func _apply_level_up() -> void:
	pass


## Pushes attribute-derived stats to their consumers. PlayerState recomputes
## itself off derived_stats_changed; the player's DamageReceiver (per-scene,
## found via group "player_health") is pushed to directly.
func _apply_attributes() -> void:
	_apply_health_to_receiver()
	derived_stats_changed.emit()


func _on_node_added(node: Node) -> void:
	if node.is_in_group("player_health") and node is DamageReceiver:
		_player_receiver = node
		# node_added fires before the receiver's _ready, so plain property sets
		# here let _ready initialise health to the CON-boosted maximum.
		_player_receiver.max_health = player_max_health()
		_player_receiver.health_regen = player_health_regen()


func _apply_health_to_receiver() -> void:
	if _player_receiver == null or not is_instance_valid(_player_receiver):
		_player_receiver = get_tree().get_first_node_in_group("player_health") as DamageReceiver
	if _player_receiver == null:
		return
	_player_receiver.set_max_health(player_max_health())
	_player_receiver.health_regen = player_health_regen()
