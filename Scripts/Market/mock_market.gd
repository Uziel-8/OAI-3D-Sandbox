class_name MockMarket
extends RefCounted
## Placeholder commodity board and ambient-event pool, so the exchange has
## something to trade before a real content pipeline exists. Same standing as
## MockItemDatabase / MockSpellbook / MockSkillTrees: REPLACE it, don't extend it,
## once commodities are authored as .tres and can be saved.
##
## Commodities come in RIVAL PAIRS -- see Commodity.rival for why. Keep the pairing
## symmetrical when adding to this list.

static func _make(id: StringName, display_name: String, unit_name: String, base_price: int,
		rival: StringName, color: Color, volatility: float, description: String) -> Commodity:
	var c := Commodity.new()
	c.id = id
	c.display_name = display_name
	c.unit_name = unit_name
	c.base_price = base_price
	c.rival = rival
	c.color = color
	c.volatility = volatility
	c.description = description
	return c


## The whole board. Three pairs: heavy industry, staple food, and cloth.
static func commodities() -> Array[Commodity]:
	return [
		_make(&"iron", "Iron Ingots", "ingot", 45, &"timber", Color(0.62, 0.66, 0.72), 1.0,
			"Bar stock off the foundry floor. The yards want it for fittings and nails; "
			+ "when it's scarce they build in wood instead."),
		_make(&"timber", "Ship Timber", "beam", 30, &"iron", Color(0.66, 0.48, 0.28), 1.0,
			"Seasoned beams for hulls and cranes. The cheap substitute when iron is dear, "
			+ "and the first thing dropped when it isn't."),
		_make(&"grain", "Grain", "sack", 12, &"saltfish", Color(0.85, 0.75, 0.40), 1.2,
			"Sacked barley and wheat. Everyone eats; the only question is what."),
		_make(&"saltfish", "Salt Fish", "barrel", 18, &"grain", Color(0.50, 0.68, 0.72), 1.2,
			"Barrelled and brined. What the docks live on in a bad harvest, and what "
			+ "nobody touches in a good one."),
		_make(&"silk", "Bolt Silk", "bolt", 120, &"wool", Color(0.72, 0.45, 0.78), 1.4,
			"Southern cloth, taxed at every border it crosses. Thin margins, violent swings."),
		_make(&"wool", "Wool", "bale", 40, &"silk", Color(0.80, 0.78, 0.70), 0.9,
			"Baled and local. Unglamorous, but it never stops selling -- and it sells "
			+ "twice as well whenever the silk road closes."),
	]


static func _event(id: StringName, headline: String, commodity: StringName, magnitude: float,
		decay_days: int, detail: String, rumour: String) -> MarketEvent:
	var e := MarketEvent.new()
	e.id = id
	e.headline = headline
	e.commodity = commodity
	e.magnitude = magnitude
	e.decay_days = decay_days
	e.detail = detail
	e.rumour = rumour
	return e


## World-driven events MarketSystem rolls from as days pass. These are the ones the
## player does NOT cause -- which is what makes a held position genuinely risky, and
## what makes it worth asking a broker what he's heard. Each carries a `rumour`,
## since ambient events are scheduled a few days ahead rather than landing at once.
static func ambient_events() -> Array[MarketEvent]:
	return [
		_event(&"bad_harvest", "Blight in the river fields", &"grain", 0.55, 7,
			"Half the upriver barley came in black. The granaries are buying anything sacked.",
			"They say the barley upriver came in black this year. I'd not want to be short of grain."),
		_event(&"good_harvest", "Barges heavy with barley", &"grain", -0.35, 6,
			"A fat harvest, and all of it arriving at once. Grain is cheap and getting cheaper.",
			"Word from upriver is the harvest is enormous. Grain'll be worth nothing by week's end."),
		_event(&"foundry_strike", "Foundrymen walk out", &"iron", 0.45, 5,
			"No smoke off the foundry stacks for three days now. The yards are already "
			+ "switching their orders to timber.",
			"The foundrymen are talking about walking out. Nobody's saying when."),
		_event(&"iron_convoy", "Ore convoy arrives early", &"iron", -0.30, 5,
			"Six barges of ore, a week ahead of the manifest. The foundries can barely store it.",
			"There's an ore convoy running early, I hear. Iron's about to get cheap."),
		_event(&"embargo", "Southern road closed", &"silk", 0.75, 8,
			"Every silk caravan is stopped at the border and the tax farmers are enjoying "
			+ "themselves. Wool is suddenly respectable.",
			"There's trouble on the southern road. If it closes, silk goes through the roof."),
		_event(&"silk_flood", "Silk fleet makes port", &"silk", -0.45, 6,
			"Three holds of southern cloth landed on the same tide. Prices are in freefall.",
			"A silk fleet's a week out, they reckon. Whoever's holding bolts should sell."),
		_event(&"fleet_lost", "Fishing fleet caught in the gale", &"saltfish", 0.50, 6,
			"Half the boats didn't come back and the ones that did came back empty.",
			"That gale's still building out east. The fishing fleet's still out in it."),
		_event(&"shipworm", "Shipworm found in the timber yards", &"timber", 0.40, 5,
			"Two yards' worth of beams condemned. What's left is worth what the buyers say.",
			"There's shipworm in one of the timber yards. They're keeping it quiet."),
	]
