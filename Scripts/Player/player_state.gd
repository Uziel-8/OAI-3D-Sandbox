extends Node
class_name PlayerStateSystem
## Global player resources that aren't health or XP: gold, plus the mana and
## stamina pools. Registered as the `PlayerState` autoload so the HUD and any
## gameplay system can read/spend them from anywhere; persists across scene
## reloads.
##
## Pools are LIVE: spells spend mana (Spell.try_pay_cost) and sprinting drains
## stamina (proto_controller), with a short delay after any spend before regen
## resumes. The pools' caps/regen are the exported bases modified by attributes
## (PlayerProgression): INT adds max mana, WIL multiplies mana regen, DEX
## multiplies stamina regen. Gold still has no source/sink beyond the API --
## the future economy/bribery systems will drive it.

signal gold_changed(gold: int)
signal mana_changed(mana: float, max_mana: float)
signal stamina_changed(stamina: float, max_stamina: float)

@export var starting_gold: int = 50
@export var base_max_mana: float = 100.0
@export var base_max_stamina: float = 100.0
@export var base_mana_regen_per_second: float = 8.0
@export var base_stamina_regen_per_second: float = 15.0
## Seconds after spending mana/stamina before that pool starts regenerating.
@export var mana_regen_delay: float = 0.5
@export var stamina_regen_delay: float = 1.0

var gold: int
var mana: float
var stamina: float
var max_mana: float
var max_stamina: float

var _mana_delay_left: float = 0.0
var _stamina_delay_left: float = 0.0


func _ready() -> void:
	gold = starting_gold
	max_mana = base_max_mana
	max_stamina = base_max_stamina
	var prog := _progression()
	if prog:
		prog.derived_stats_changed.connect(_refresh_derived)
		max_mana = base_max_mana + prog.bonus_max_mana()
	mana = max_mana
	stamina = max_stamina


func _process(delta: float) -> void:
	_mana_delay_left = maxf(_mana_delay_left - delta, 0.0)
	_stamina_delay_left = maxf(_stamina_delay_left - delta, 0.0)
	if _mana_delay_left <= 0.0 and mana < max_mana:
		mana = minf(mana + mana_regen_per_second() * delta, max_mana)
		mana_changed.emit(mana, max_mana)
	if _stamina_delay_left <= 0.0 and stamina < max_stamina:
		stamina = minf(stamina + stamina_regen_per_second() * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)


func _progression() -> ProgressionSystem:
	return get_node_or_null("/root/PlayerProgression") as ProgressionSystem


## Current regen rates including attribute multipliers (WIL / DEX).
func mana_regen_per_second() -> float:
	var prog := _progression()
	return base_mana_regen_per_second * (prog.mana_regen_multiplier() if prog else 1.0)


func stamina_regen_per_second() -> float:
	var prog := _progression()
	return base_stamina_regen_per_second * (prog.stamina_regen_multiplier() if prog else 1.0)


## Recomputes attribute-derived caps, keeping current values (clamped).
func _refresh_derived() -> void:
	var prog := _progression()
	if prog == null:
		return
	max_mana = base_max_mana + prog.bonus_max_mana()
	mana = minf(mana, max_mana)
	mana_changed.emit(mana, max_mana)
	stamina_changed.emit(stamina, max_stamina)


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func spend_mana(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if mana < amount:
		return false
	mana -= amount
	_mana_delay_left = mana_regen_delay
	mana_changed.emit(mana, max_mana)
	return true


func restore_mana(amount: float) -> void:
	mana = minf(mana + amount, max_mana)
	mana_changed.emit(mana, max_mana)


func spend_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if stamina < amount:
		return false
	stamina -= amount
	_stamina_delay_left = stamina_regen_delay
	stamina_changed.emit(stamina, max_stamina)
	return true


func restore_stamina(amount: float) -> void:
	stamina = minf(stamina + amount, max_stamina)
	stamina_changed.emit(stamina, max_stamina)
