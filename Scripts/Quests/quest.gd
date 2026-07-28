class_name Quest
extends Resource
## One sidequest, authored as a .tres under Resources/Quests/ and assigned to a
## QuestGiver component on the NPC who offers it.
##
## Everything about a quest lives in this one file -- its identity, its four
## state-aware dialogue line sets, and its rewards -- the way NpcProfile holds
## everything about one NPC archetype. What it does NOT hold is where its steps
## are: those are LevelObjective components placed in the LEVEL with their `quest`
## export pointed here (a shared resource can't reference world instances, exactly
## like Npc.patrol_points).
##
## Authoring a new quest: new .tres here, fill the lines/rewards, drop a QuestGiver
## on an NPC with this in its `quests`, then drop objective components in the level
## pointing at it. No code changes.

## Unique key for this quest -- the id used by QuestSystem's state store and by
## other quests' `prerequisites`. Must be unique across the game.
@export var id: StringName = &""
## Shown in the journal list, the HUD tracker, and the accept/complete toasts.
@export var title: String = "Untitled Quest"
## The journal body: what the giver wants and why.
@export_multiline var summary: String = ""
## Shown in the journal as "Given by ...". Blank = omitted.
@export var giver_name: String = ""

## Quest ids that must be COMPLETED before this one is offered. A DAG, like
## SkillNode.prerequisites -- branches can converge. Empty = always offerable.
@export var prerequisites: Array[StringName] = []

## When true the player must return to the giver to hand it in (the quest sits in
## READY once its objectives are done). When false it completes and pays out the
## instant the last objective ticks.
@export var requires_turn_in: bool = true

@export_group("Dialogue")
## The pitch, shown while the quest is offerable.
@export var offer_lines: Array[String] = []
## Label on the accept button.
@export var accept_text: String = "I'll do it."
## The giver's reply after accepting. Blank = close immediately.
@export_multiline var accept_response: String = ""
## Label on the decline button. Blank = no decline button (Esc still closes).
@export var decline_text: String = "Not now."
## Said while the quest is active but unfinished.
@export var in_progress_lines: Array[String] = []
## Said once every objective is done and the quest awaits turn-in.
@export var ready_lines: Array[String] = []
## Label on the turn-in button.
@export var turn_in_text: String = "It's done."
## The giver's reply on turn-in. Blank = close immediately.
@export_multiline var turn_in_response: String = ""
## Said after the quest is completed. EMPTY = fall back to the NPC's normal
## profile dialogue, so a one-off errand doesn't silence the NPC forever.
@export var completed_lines: Array[String] = []

@export_group("Rewards")
## Awarded via PlayerProgression.add_experience.
@export var xp_reward: float = 0.0
## Awarded via PlayerState.add_gold.
@export var gold_reward: int = 0
## Awarded via PlayerProgression.grant_skill_points -- spendable in the magic trees.
@export var skill_point_reward: int = 0
## Added to the GIVER's own disposition on turn-in. Can trip a DispositionReaction
## (opening a gate, etc.) with no extra wiring.
@export var giver_disposition: int = 0
## Standing shifts with whole factions, applied through the Reputation autoload.
@export var faction_rewards: Array[FactionReward] = []


## True when this quest has no way to be completed by the player other than the
## giver dying -- used only for warnings. A quest with no objectives at all is
## legal (a pure "go talk to X" turn-in), so this is informational.
func has_rewards() -> bool:
	return xp_reward > 0.0 or gold_reward > 0 or skill_point_reward > 0 \
		or giver_disposition != 0 or not faction_rewards.is_empty()


## One-line reward summary for the journal, e.g. "75 XP  •  60 gold".
func reward_text() -> String:
	var parts: Array[String] = []
	if xp_reward > 0.0:
		parts.append("%d XP" % int(xp_reward))
	if gold_reward > 0:
		parts.append("%d gold" % gold_reward)
	if skill_point_reward > 0:
		parts.append("%d skill point%s" % [skill_point_reward, "" if skill_point_reward == 1 else "s"])
	for reward in faction_rewards:
		if reward and reward.delta != 0:
			parts.append("%s %+d standing" % [String(reward.faction).capitalize(), reward.delta])
	return "  •  ".join(parts)
