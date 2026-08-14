class_name Commodity
extends Resource
## One tradable good on the guild's board. Data only -- prices, positions and every
## rule about them live in MarketSystem; this is just what a commodity IS.
##
## The important field is `rival`. Commodities are authored in PAIRS that move
## against each other (iron vs timber, grain vs salt fish), and every market event
## automatically pushes the rival the opposite way. That is what removes the need
## for short-selling: sabotaging a supply chain always has a long side to be on, so
## "wreck the thing, profit from the wreck" works with nothing but buy and sell.
## Keep pairings symmetrical (if iron's rival is timber, timber's rival is iron) --
## MarketSystem doesn't enforce it, and a one-way pairing quietly makes one half of
## the pair a better trade than the other.

## Unique key. What holdings, effects and MarketEvent.commodity are keyed on.
@export var id: StringName = &""
@export var display_name: String = "Commodity"
@export_multiline var description: String = ""
## What one unit is called in prose, e.g. "crate", "bolt", "bushel".
@export var unit_name: String = "unit"
## The price with no events acting on it. Prices always decay back toward this.
@export var base_price: int = 20
## Row accent on the market screen. No art pipeline yet, same as InventoryItem.
@export var color: Color = Color(0.6, 0.6, 0.65)
## The commodity that moves the OPPOSITE way when this one is hit. Blank = no pair,
## and events on it have no counterparty.
@export var rival: StringName = &""
## Scales how hard ambient (non-player) events hit this good. 1.0 = as authored.
@export var volatility: float = 1.0


## Two-letter fallback glyph, matching InventoryItem.icon_text() while there's no art.
func icon_text() -> String:
	var clean := display_name.strip_edges()
	if clean.is_empty():
		return "?"
	var parts := clean.split(" ", false)
	if parts.size() >= 2:
		return (parts[0][0] + parts[1][0]).to_upper()
	return clean.substr(0, mini(2, clean.length())).to_upper()
