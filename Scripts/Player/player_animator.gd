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
## `animation_tree`. The ROOT is a BlendTree so the cast/hurt/land overlays can layer on
## top of the movement state machine, which is NESTED inside it as a node named "Movement":
##
##   Root  AnimationNodeBlendTree
##     Movement   AnimationNodeStateMachine  -- states "Grounded"/"Jump"/"Fall" (code travels these)
##                  Grounded = BlendSpace1D  (Idle_B -> Walking_B -> Running_B)
##     CastBlend  Blend2   -- blends Movement vs a looping Ranged_Magic_Spellcasting (HELD casts),
##                            filtered to spine/arms
##     CastShot   OneShot  -- fires Ranged_Magic_Shoot for INSTANT casts, upper-body filtered   [add for per-spell casts]
##     HurtShot   OneShot  -- layers Hit_A on top, upper-body filtered
##     LandShot   OneShot  -- fires Jump_Land on landing, full body (no filter)                  [add for land polish]
##     wiring:  Movement -> CastBlend(A) ; spellcasting clip -> CastBlend(B) ;
##              CastBlend -> CastShot -> HurtShot -> LandShot -> Output  (overlays chained)
##
## CastShot/LandShot are optional polish -- until you add them, play_cast_shot()/play_land()
## set() a path that doesn't exist yet and no-op SILENTLY (held casts + everything else still
## work). Nested nodes take their parent's name as a path prefix (hence "Movement/"). These
## MUST match the authored graph: AnimationTree.set() on a wrong path fails SILENTLY, so the
## paths live in the PARAM_* constants below. Death bypasses the tree entirely (see play_death).

## AnimationTree parameter paths driven by this script -- keep in sync with the graph above.
const PARAM_PLAYBACK := "parameters/Movement/playback"
const PARAM_LOCOMOTION := "parameters/Movement/Grounded/blend_position"
const PARAM_CAST_BLEND := "parameters/CastBlend/blend_amount"
const PARAM_CAST_SHOT_REQUEST := "parameters/CastShot/request"
const PARAM_HURT_REQUEST := "parameters/HurtShot/request"
const PARAM_LAND_REQUEST := "parameters/LandShot/request"

@export var animation_tree: AnimationTree
@export var animation_player: AnimationPlayer

@export_group("Fallback clips (used only when no AnimationTree assigned)")
@export var idle_anim: String = "Rig_Medium_General/Idle_B"
@export var walk_anim: String = "Rig_Medium_MovementBasic/Walking_B"
@export var run_anim: String = "Rig_Medium_MovementBasic/Running_B"
@export var jump_anim: String = "Rig_Medium_MovementBasic/Jump_Start"
@export var fall_anim: String = "Rig_Medium_MovementBasic/Jump_Idle"
## Instant-cast clip (Fireball/Ice Bolt/Push). Held casts use the looping
## Ranged_Magic_Spellcasting inside the tree's CastBlend instead.
@export var cast_anim: String = "Rig_Medium_CombatRanged/Ranged_Magic_Shoot"
@export var hurt_anim: String = "Rig_Medium_General/Hit_A"
@export var land_anim: String = "Rig_Medium_MovementBasic/Jump_Land"
@export var death_anim: String = "Rig_Medium_General/Death_A"

@export_group("Cast overlay")
## How fast the held-cast overlay fades in/out (per second).
@export var cast_blend_speed: float = 9.0

var _playback: AnimationNodeStateMachinePlayback
var _caster: SpellCaster
var _cast_amount: float = 0.0
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

	# Held-cast overlay: raised (upper body) while a HELD spell is active, eased back
	# down otherwise. Instant casts use the CastShot one-shot instead (see _on_spell_cast).
	var casting := _caster != null and _caster.is_casting()
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


## Fire the instant-cast one-shot (Ranged_Magic_Shoot). Held casts use CastBlend.
func play_cast_shot() -> void:
	if animation_tree:
		animation_tree.set(PARAM_CAST_SHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif animation_player:
		animation_player.play(cast_anim, 0.1)


## Fire the landing one-shot (Jump_Land). Called by FallState on touchdown.
func play_land() -> void:
	if animation_tree:
		animation_tree.set(PARAM_LAND_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif animation_player:
		animation_player.play(land_anim, 0.05)


## Play the full-body death clip. Deactivates the AnimationTree so the plain
## AnimationPlayer drives the skeleton (Death isn't a movement-SM state), so this
## needs no tree authoring. The scene reloads shortly after (DeadState), spawning
## a fresh player with the tree active again.
func play_death() -> void:
	if animation_tree:
		animation_tree.active = false
	if animation_player:
		animation_player.play(death_anim, 0.2)


func _on_spell_cast(spell: Spell) -> void:
	# Instant spells get a quick shot flourish; held spells are handled by the
	# sustained CastBlend overlay in _process (via SpellCaster.is_casting()).
	if spell != null and spell.instant:
		play_cast_shot()


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
