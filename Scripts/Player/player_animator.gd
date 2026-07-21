extends Node
class_name PlayerAnimator
## The seam between gameplay states and animation. States never touch the
## AnimationTree/Player directly -- they call travel()/set_locomotion()/play_hurt()
## here, and this drives the assigned AnimationTree (the real path) OR falls back
## to AnimationPlayer.play() on mapped clips so the character still animates before
## the tree is authored. It also owns the upper-body CAST overlay, driven off the
## SpellCaster's spell_cast signal / is_casting() (casting doesn't change gameplay
## state -- you can cast while moving).
##
## ANIMATIONTREE CONTRACT -- author this graph in the editor, then assign the tree to
## `animation_tree`. The ROOT is a BlendTree so the cast/hurt overlays can layer on top
## of the movement state machine, which is NESTED inside it as a node named "Movement":
##
##   Root  AnimationNodeBlendTree
##     Movement   AnimationNodeStateMachine  -- states "Grounded"/"Jump"/"Fall" (code travels these)
##                  Grounded = BlendSpace1D  (Idle_B -> Walking_B -> Running_B)
##     CastBlend  Blend2   -- blends Movement vs a looping Ranged_Magic_Spellcasting, filtered to spine/arms
##     HurtShot   OneShot  -- layers Hit_A on top, upper-body filtered
##     wiring:  Movement -> CastBlend(A) ; cast clip -> CastBlend(B) ; CastBlend -> HurtShot -> Output
##
## Nested nodes take their parent's name as a path prefix -- that's why the movement paths
## are under "Movement/". These MUST match the authored graph: AnimationTree.set() on a
## wrong path fails SILENTLY, so the paths live in the PARAM_* constants below.

## AnimationTree parameter paths driven by this script -- keep in sync with the graph above.
const PARAM_PLAYBACK := "parameters/Movement/playback"
const PARAM_LOCOMOTION := "parameters/Movement/Grounded/blend_position"
const PARAM_CAST_BLEND := "parameters/CastBlend/blend_amount"
const PARAM_HURT_REQUEST := "parameters/HurtShot/request"

@export var animation_tree: AnimationTree
@export var animation_player: AnimationPlayer

@export_group("Fallback clips (used only when no AnimationTree assigned)")
@export var idle_anim: String = "Rig_Medium_General/Idle_B"
@export var walk_anim: String = "Rig_Medium_MovementBasic/Walking_B"
@export var run_anim: String = "Rig_Medium_MovementBasic/Running_B"
@export var jump_anim: String = "Rig_Medium_MovementBasic/Jump_Start"
@export var fall_anim: String = "Rig_Medium_MovementBasic/Jump_Idle"
@export var cast_anim: String = "Rig_Medium_CombatRanged/Ranged_Magic_Shoot"
@export var hurt_anim: String = "Rig_Medium_General/Hit_A"

@export_group("Cast overlay")
## How fast the cast overlay fades in/out (per second).
@export var cast_blend_speed: float = 9.0
## How long an instant cast keeps the overlay up after firing.
@export var cast_flourish_time: float = 0.45

var _playback: AnimationNodeStateMachinePlayback
var _caster: SpellCaster
var _cast_amount: float = 0.0
var _cast_timer: float = 0.0
var _fallback_clip: String = ""


func _ready() -> void:
	add_to_group("player_animator")
	if animation_tree:
		animation_tree.active = true
		_playback = animation_tree.get(PARAM_PLAYBACK)


func _process(delta: float) -> void:
	# Bind to the SpellCaster lazily so we don't depend on _ready() ordering
	# (it may not be in its group yet when this node readies).
	if _caster == null or not is_instance_valid(_caster):
		_caster = get_tree().get_first_node_in_group("spell_caster") as SpellCaster
		if _caster and not _caster.spell_cast.is_connected(_on_spell_cast):
			_caster.spell_cast.connect(_on_spell_cast)

	# Upper-body cast overlay: raised while an instant flourish is timing out or a
	# held spell is active, eased back down otherwise. Independent of movement.
	_cast_timer = maxf(_cast_timer - delta, 0.0)
	var casting := _cast_timer > 0.0 or (_caster != null and _caster.is_casting())
	_cast_amount = move_toward(_cast_amount, 1.0 if casting else 0.0, cast_blend_speed * delta)
	if animation_tree:
		animation_tree.set(PARAM_CAST_BLEND, _cast_amount)


## Move the full-body playback to a gameplay state ("Grounded"/"Jump"/"Fall").
func travel(state_name: StringName) -> void:
	if _playback:
		_playback.travel(state_name)
	else:
		_fallback_travel(state_name)


## Set the grounded locomotion blend, 0 (idle) .. 1 (full run).
func set_locomotion(speed01: float) -> void:
	speed01 = clampf(speed01, 0.0, 1.0)
	if animation_tree:
		animation_tree.set(PARAM_LOCOMOTION, speed01)
	else:
		_fallback_locomotion(speed01)


## Fire a one-shot hurt flinch (upper body). Called on DamageReceiver.damaged.
func play_hurt() -> void:
	if animation_tree:
		animation_tree.set(PARAM_HURT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif animation_player:
		animation_player.play(hurt_anim, 0.1)


func _on_spell_cast(_spell: Spell) -> void:
	_cast_timer = cast_flourish_time
	# In fallback mode there's no upper-body layer, so show the cast full-body.
	if animation_tree == null and animation_player:
		animation_player.play(cast_anim, 0.1)


# --- Fallback (no AnimationTree) ---------------------------------------------

func _fallback_travel(state_name: StringName) -> void:
	match String(state_name):
		"Jump":
			_play_fallback(jump_anim)
		"Fall":
			_play_fallback(fall_anim)
		# "Grounded" is driven by set_locomotion instead.


func _fallback_locomotion(speed01: float) -> void:
	var clip := idle_anim if speed01 < 0.1 else (walk_anim if speed01 < 0.6 else run_anim)
	_play_fallback(clip)


func _play_fallback(clip: String) -> void:
	if clip == _fallback_clip or animation_player == null:
		return
	_fallback_clip = clip
	animation_player.play(clip, 0.15)
