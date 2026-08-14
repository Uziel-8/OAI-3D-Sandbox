class_name MarketEvent
extends Resource
## Something that happened in the world, expressed as a price move. Authored as a
## .tres under Resources/Market/ (or inline on a trigger), then fired either by a
## MarketEventTrigger placed in the level, by a quest reward, or by MarketSystem's
## own ambient roll.
##
## An event knows nothing about WHO caused it -- MarketSystem is told that at fire
## time, because the same "warehouse burns" event is insider trading when the player
## lit it and just news when it burned on its own.
##
## `magnitude` is a FRACTION of base price, not a gold amount: -0.4 means "this good
## loses 40% of its base value", so one event resource reads the same on a 12g
## bushel and a 120g bolt of silk. The rival commodity automatically moves the other
## way by `rival_scale` of that -- see Commodity.rival.

## Unique key, used for de-duplication and for matching a rumour to its event.
@export var id: StringName = &""
## The line the guild board / HUD toast shows, e.g. "Dockside warehouse burns".
@export var headline: String = "Market moves"
## Longer text for the market screen's news column.
@export_multiline var detail: String = ""

## Which good this hits.
@export var commodity: StringName = &""
## Fraction of base price, signed. +0.5 = half again as dear, -0.4 = down 40%.
@export_range(-1.0, 3.0, 0.05) var magnitude: float = 0.25
## Days for the move to fade back to nothing (linear). This is the WINDOW the player
## has to sell into -- a spike nobody sells is a spike wasted.
@export var decay_days: int = 6
## How much of the (negated) magnitude lands on the rival commodity. 0 = no
## counterparty move.
@export_range(0.0, 1.0, 0.05) var rival_scale: float = 0.6

@export_group("Rumours")
## Shown by a broker before the event lands, when it was scheduled ahead. Blank =
## the event arrives unannounced.
@export_multiline var rumour: String = ""


## Human-readable direction, for the news column and rumour prose.
func direction_text() -> String:
	if magnitude > 0.0:
		return "rising"
	elif magnitude < 0.0:
		return "falling"
	return "steady"
