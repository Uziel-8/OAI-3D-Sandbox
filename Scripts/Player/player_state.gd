extends Node
class_name PlayerStateSystem
## Global player resources that aren't health or XP: gold, plus the mana and
## stamina pools. Registered as the `PlayerState` autoload so the HUD and any
## gameplay system can read/spend them from anywhere; persists across scene
## reloads.
##
## PLACEHOLDER: nothing spends mana or stamina yet (spells are free, sprint is
## free), so both sit full and regen is invisible. The spend/restore API and
## passive regen exist so spell costs / sprint drain can hook in later without
## the HUD changing. Gold has no source/sink yet beyond add_gold()/spend_gold()
## -- the future economy/bribery systems will drive it. Starting gold is seeded
## so the counter shows something and bribery is testable.

signal gold_changed(gold: int)
signal mana_changed(mana: float, max_mana: float)
signal stamina_changed(stamina: float, max_stamina: float)

@export var starting_gold: int = 50
@export var max_mana: float = 100.0
@export var max_stamina: float = 100.0
@export var mana_regen_per_second: float = 8.0
@export var stamina_regen_per_second: float = 15.0

var gold: int
var mana: float
var stamina: float


func _ready() -> void:
	gold = starting_gold
	mana = max_mana
	stamina = max_stamina


func _process(delta: float) -> void:
	if mana < max_mana:
		mana = minf(mana + mana_regen_per_second * delta, max_mana)
		mana_changed.emit(mana, max_mana)
	if stamina < max_stamina:
		stamina = minf(stamina + stamina_regen_per_second * delta, max_stamina)
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
	stamina_changed.emit(stamina, max_stamina)
	return true


func restore_stamina(amount: float) -> void:
	stamina = minf(stamina + amount, max_stamina)
	stamina_changed.emit(stamina, max_stamina)
