class_name StartScreen
extends CanvasLayer
## WALL CLOCK BY DESIGN: the warming budget below is a share of a REAL frame,
## spent while the tree is paused and the simulation clock is deliberately not
## running. It is the loader measuring the machine, not the world measuring
## itself.
##
## WHAT A PHONE CANNOT REACH.
##
## Five things live on function keys: help (F1), the graphics tier (F2), the
## debug menu (F3), skipping the tutorial (F4) and the creature profiles (F5).
## On a keyboard that is exactly right — they are there when you want them and
## out of the way when you do not. On a thumb there is no F1, and so there is
## no help, no way to change quality, and no way to skip a tutorial you have
## already sat through four times. They were simply gone.
##
## So they are all here, once, at the start, where a player is already deciding
## what kind of session this is going to be. It is not a main menu with a New
## Game button — the world is already made and standing behind this — it is the
## moment before you begin, and everything you might want to have settled first.
##
## THE WORLD IS HELD WHILE IT IS UP, AND STILL LOADING. Nothing ages, nothing
## starves, nobody walks anywhere — a player who reads every line of the help
## should not come back to a village that lived through it.
##
## But a paused tree does not stream chunks either, and streaming is most of
## what "loading" means here; pause everything and the one thing you wanted to
## happen behind the screen is the one thing that stops. So the pause is real
## and the loader is exempt from it by name: WorldGen runs always and marks
## every chunk it spawns pausable, so while the screen is up the only thing
## happening in the world is ground arriving. See WorldGen._process.

## HOW MUCH OF A FRAME THE WARMING MAY HAVE, in milliseconds.
##
## It was two JOBS a frame, which is not a budget — it is a guess about how
## long a job takes, and the jobs here range from a dictionary probe to
## synthesizing a two-second waveform. Sixty-odd steps at two a frame is half a
## second of warming, and then the screen sat there saying "Ready." while the
## expensive thing (the world's cold fill, hundreds of chunks) went on
## streaming behind it — and handed over the instant somebody pressed Begin.
##
## A millisecond budget fills whatever headroom the frame actually has, on
## whatever machine it actually is, and the screen no longer lets go until the
## land is laid. See `_ready_to_begin`.
const WARM_MILLIS := 5.0

## WHAT THE WAIT IS WORTH, as a share of the bar: the caches and the land. The
## land is most of it because the land IS most of it.
const CACHES_WORTH := 0.25

## AND A LIMIT ON HOW LONG ANYBODY IS HELD, in real seconds. A disabled Begin
## is the worst failure this screen can have — if the far ring never reports
## itself full, for any reason at all, the player is locked out of their own
## game with no way to say so. So the wait has an end whatever the loader
## thinks. Generous: the cold fill is a couple of seconds on a flagship and
## perhaps ten on a throttled phone, so this is never reached in an ordinary
## run and is only ever there for the run that goes wrong.
const PATIENCE := 45.0


var profiles: ProfileMenu = null

var _panel: PanelContainer
var _backdrop: ColorRect
var _quality_button: Button
var _progress: Label
var _begin: Button
var _logo: LogoGame
var _waiting_to_name := false
var _begun := false
var _caches_warm := false
var _waited := 0.0
var _warm_jobs: Array[Callable] = []


func _ready() -> void:
	layer = 12          # under the profile menu, which is its own modal
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_fill_warm_jobs()
	# THE FIRST RUN NAMES THE CREATURE FIRST. ProfileMenu opens itself when
	# there are no profiles, and naming the thing you are about to raise is
	# the right first act of a god — this comes after it, not over it.
	_waiting_to_name = SaveGame.profiles.is_empty()
	if _waiting_to_name:
		_hold()          # hold the world anyway, so the naming costs nothing
	else:
		_show()


## REAL SECONDS, and deliberately: the tree is paused here and GameState.clock
## is stopped, which is exactly right for a world that is not supposed to be
## living yet and exactly wrong for a loader waiting on a machine.
func _process(delta: float) -> void:
	if _waiting_to_name:
		if profiles == null or not profiles.is_open():
			_waiting_to_name = false
			_show()
		return
	if not _begun:
		_waited += delta
		_warm()          # including while the first creature is being named
		_refresh_begin()


## THE THINGS THAT WOULD OTHERWISE HITCH LATER, done now while somebody reads.
##
## Every one of these is a cache that builds itself the first time it is asked
## for: the sound bank synthesizes twenty-four waveforms, the model bank hits
## the filesystem once per name it has never looked for, and the herd's pose
## table is built on the first frame a herd is drawn. Left alone they land on
## the first wolf, the first sheep and the first herd over the hill — which is
## to say, all in the first ten seconds, together.
func _fill_warm_jobs() -> void:
	_warm_jobs.append(func() -> bool: return SoundBank.warm_next())
	var names: Array = ModelBank.KNOWN.duplicate()
	names.append_array(Animal.SPECIES.keys())
	_warm_jobs.append(func() -> bool:
		if names.is_empty():
			return false
		ModelBank.has(names.pop_back())
		return true)
	# One pose table for the whole world, built once and then only refreshed.
	_warm_jobs.append(func() -> bool:
		HerdMotion.refresh(0.0)
		return false)
	# THE REST OF THE LAZY CACHES, each of which builds itself the first time
	# anything asks and every one of which was landing mid-game: the two
	# procedural textures every flame, torch and mark in the world is drawn
	# with, the blossom the orchards use, the ground material under all of it,
	# the rune templates the recogniser matches against, and the cloud.
	var once := [
		func() -> void: Util.dot_mesh(0.1, Color.WHITE),
		func() -> void: Util.flame_mesh(0.4, 0.6),
		func() -> void: Util.speck_mesh(0.1, 0.1, Color.WHITE, true),
		func() -> void: Util.blossom_mesh(),
		func() -> void: Util.blossom_material(),
		func() -> void: Util.ground_material(),
		func() -> void: GestureRecognizer.warm(),
		func() -> void: StormCloud.vapour_texture(),
		func() -> void: SkyCover.texture(),
	]
	_warm_jobs.append(func() -> bool:
		if once.is_empty():
			return false
		(once.pop_back() as Callable).call()
		return true)


## WARM UNTIL THE FRAME'S SHARE IS SPENT. A budget rather than a count, because
## the jobs are not the same size as each other and the machines are not the
## same size as each other.
func _warm() -> void:
	var until := Time.get_ticks_msec() + WARM_MILLIS
	while not _caches_warm and Time.get_ticks_msec() < until:
		var busy := false
		for job in _warm_jobs:
			if job.call():
				busy = true
				break
		_caches_warm = not busy
	_progress.text = _where_we_are()


## WHAT THE BAR SAYS. The caches first and then the land, because that is the
## order they finish in and because naming the land is the honest answer to
## "what is it doing" — it is building the world you are about to stand in.
func _where_we_are() -> String:
	var share := 0.0
	if _caches_warm:
		share = CACHES_WORTH + (1.0 - CACHES_WORTH) * _land()
	else:
		# The sound bank is by far the bulk of the caches — twenty-six
		# waveforms — so its share is a fair reading of that quarter.
		share = CACHES_WORTH * SoundBank.warmth()
	if _ready_to_begin():
		return "Ready."
	var what := "Laying out the land" if _caches_warm else "Making ready"
	return "%s... %d%%" % [what, int(share * 100.0)]


func _land() -> float:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	return world.land_progress() if world != null else 1.0


## THE SCREEN DOES NOT LET GO UNTIL THE WORLD IS THERE. This is the whole of
## the first-run slowness: the streamer runs behind this screen on purpose, and
## then the screen handed over the moment somebody pressed Begin, delivering
## the rest of the cold fill into their first ten seconds of play.
func _ready_to_begin() -> bool:
	if _waited > PATIENCE:
		return true      # see PATIENCE: nobody is locked out of their own game
	return _caches_warm and _land() >= 1.0


func _refresh_begin() -> void:
	if _begin == null:
		return
	var can := _ready_to_begin()
	_begin.disabled = not can
	_begin.text = "Begin" if can else "Making ready..."


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.01, 0.03, 0.72)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 0.95)
	style.border_color = Color(1.0, 0.86, 0.5, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.add_child(_heading("Hand of the Heavens"))

	# THE TOY, ABOVE EVERYTHING ELSE. It is the first thing on the screen
	# because it is the thing the player is meant to do while the land arrives,
	# and because drawing on it with a finger is the one control the game does
	# not otherwise teach. See LogoGame.
	_logo = LogoGame.new()
	_logo.custom_minimum_size = Vector2(220, 220)
	_logo.finished.connect(_on_logo_turned)
	rows.add_child(_logo)
	rows.add_child(_note("Draw on it while the land is laid out."
		+ " Everything below can be changed later on a keyboard."))

	_quality_button = _row("", _on_quality)
	rows.add_child(_quality_button)
	rows.add_child(_row("Your creatures  [F5]", _fire.bind("toggle_profiles")))
	# The temple's real door is holding the sun, which nobody discovers by
	# accident. One line here is what makes the gesture findable at all.
	rows.add_child(_row("The temple — or hold the sun  [F6]",
		_fire.bind("toggle_temple")))
	rows.add_child(_row("How to play  [F1]", _fire.bind("toggle_help")))
	rows.add_child(_row("Skip the tutorial  [F4]", _fire.bind("skip_tutorial")))
	rows.add_child(_row("Debug menu  [F3]", _fire.bind("toggle_debug")))

	_progress = _note("")
	rows.add_child(_progress)

	_begin = _row("Making ready...", _on_begin)
	_begin.add_theme_font_size_override("font_size", 22)
	_begin.custom_minimum_size = Vector2(280, 56)
	_begin.disabled = true
	rows.add_child(_begin)

	_panel.add_child(rows)
	add_child(_panel)
	_refresh_labels()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.62))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


## Big enough for a thumb, which is the entire reason this screen exists.
func _row(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(on_press)
	return b


func _refresh_labels() -> void:
	_quality_button.text = "Graphics: %s  [F2]" \
		% str(Quality.Tier.keys()[Quality.tier]).capitalize()


## EVERY BUTTON HERE PULLS THE SAME LEVER ITS KEY DOES. Not a second copy of
## each behaviour that happens to look alike — one of those two would quietly
## rot, and it would be the one nobody on a keyboard ever presses.
func _fire(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _on_quality() -> void:
	Quality.cycle()
	_refresh_labels()


## The whole mark turned. Nothing hangs on it — it is a toy — but a toy with
## no end is a fidget, so say something.
func _on_logo_turned() -> void:
	GameState.announce("The mark is turned. Well drawn.")


func _on_begin() -> void:
	if not _ready_to_begin():
		return
	_begun = true
	_panel.visible = false
	_backdrop.visible = false
	get_tree().paused = false


func _show() -> void:
	_refresh_labels()
	_panel.visible = true
	_backdrop.visible = true
	_hold()


func _hold() -> void:
	get_tree().paused = true
