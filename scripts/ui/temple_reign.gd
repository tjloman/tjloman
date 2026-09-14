class_name TempleReign
extends ScrollContainer
## THE REIGN ROOM: where the run stands right now, in words.
##
## The charts next door show how everything got here. This is the ledger: what
## is standing, what is dead, what killed it, and how long people get to live
## under you.
##
## THE ONE NUMBER WORTH THE WHOLE ROOM is life expectancy as OBSERVED. The
## world rolls every villager a lifespan of 60 to 85 years at birth, so the
## average of that is about 72.5 in every game anybody has ever played,
## however well or badly they ruled — printing it would be printing a
## constant. The age people ACTUALLY reach, wolves and famine and lightning
## included, is a direct measure of the reign, and a cruel one drives it into
## the thirties. See Chronicle.life_expectancy.

## What each cause of death is called in a sentence, and the order they are
## listed in — worst first, because that is the one you want to see.
const GRAVES: Array[Array] = [
	["fire", "burnt"],
	["sudden", "struck down"],
	["beast", "killed by animals"],
	["war", "killed by their own kind"],
	["hunger", "starved"],
	["age", "died of old age"],
]

var world_gen: WorldGen

var _body: VBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	add_child(_body)
	_fill()


func _fill() -> void:
	var book := Chronicle.of(get_tree())
	_heading("The world as it stands")
	var towns := 0
	var faithful := 0
	var souls := 0
	for n in get_tree().get_nodes_in_group("village"):
		var town := n as Village
		if town == null or not is_instance_valid(town):
			continue
		towns += 1
		souls += town.population()
		if town.converted:
			faithful += 1
	_line("Villages standing near you", str(towns))
	_line("...of which hold your faith", str(faithful))
	_line("Souls in them", str(souls))
	_line("Villages met and left behind", str(SaveGame.village_memory.size()))
	# HOW MUCH WORLD THERE IS OF YOURS. The land is endless, so this is not a
	# fraction of anything — it is the size of the country the fog has been
	# lifted from, which is the only honest way to say how far a god has gone.
	if world_gen != null and is_instance_valid(world_gen):
		var cells := world_gen.known_count()
		var area := float(cells) * WorldGen.CHUNK_SIZE * WorldGen.CHUNK_SIZE
		_line("Land you have raised", "%.2f km²" % (area / 1000000.0))
	_line("Days elapsed", "%d" % int(GameState.game_years / GameState.DAY_YEARS))
	_line("Your alignment", "%+d" % int(roundf(GameState.alignment)))

	_heading("Wonders")
	var wonders := MiracleManager.of(get_tree())
	if wonders != null:
		_line("Miracles you have worked", str(wonders.casts_made))
		_line("Miracles the creature has worked", str(wonders.creature_casts))
		_line("Prayer power", "%d / %d"
			% [int(GameState.prayer_power), int(GameState.max_prayer_power)])

	_heading("The dead")
	if book == null or book.buried() == 0:
		_note("Nobody has died yet under your hand.")
		return
	_line("Buried in all", str(book.buried()))
	_line("Life expectancy, as lived", "%.1f years" % book.life_expectancy())
	_note("Not the 60-85 the world rolls at birth — the age people actually "
		+ "reach under you, which is the same number read honestly.")
	var burials := book.burials()
	for row: Array in GRAVES:
		var cause := String(row[0])
		if not burials.has(cause):
			continue
		var grave: Array = burials[cause]
		_line("  %s" % String(row[1]),
			"%d  (avg %.0f yrs)" % [int(grave[0]), float(grave[1])])


func _heading(text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 8.0)
	_body.add_child(gap)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	_body.add_child(label)


func _line(what: String, value: String) -> void:
	var row := HBoxContainer.new()
	var left := Label.new()
	left.text = what
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	row.add_child(left)
	var right := Label.new()
	right.text = value
	row.add_child(right)
	_body.add_child(row)


func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_body.add_child(label)
