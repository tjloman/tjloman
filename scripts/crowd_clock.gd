class_name CrowdClock
extends Node
## WHOSE TURN IT IS, ASKED ONCE A FRAME — NOT BY EVERYBODY.
##
## A crowd already lives on a slower clock: a city ticks each of its people
## every second or fourth frame (Crowd), a far town every tenth (sim_stride),
## and whose turn it is was always plain arithmetic on an id (Scheduler.turn).
## But the ENGINE does not know that. It called every villager's
## `_physics_process` on every physics step, so that each of them could work
## out that it was not their turn and return.
##
## tools/live/throng_live.gd measured what that costs, in a world of 1,448:
## about 1,270 calls a frame that did nothing, at five microseconds each, and
## the engine's own price for making the calls on top — close to half of the
## whole villager bill (22.7 ms) spent on people saying "not me".
##
## So the engine calls nobody. Each villager is booked on a wheel at the next
## frame its turn falls on — by the same arithmetic Scheduler.turn uses, on a
## seat number instead of an id (see `_seat`) — and this calls only those, with
## how many frames the turn stands for. Nobody lives any differently, thinks any
## less often or is drawn any differently.
##
## THREE THINGS RUN EVERY FRAME WHOEVER THEY ARE: held, falling and burning.
## The hand has to feel instant and a scream every fourth frame is not a
## scream (see Agitation). Whatever puts a villager into one of those says so
## (`heat`), and they are fetched forward to the next frame at once.
##
## WHAT IT TRADES: a stride is worked out on a villager's own turn, not every
## frame, so somebody ten frames from their turn notices the camera has
## arrived up to ten frames late — a third of a second at most on a cool
## device, a second on the hottest. The hand does not wait for it (`heat`).

## Frames the wheel looks ahead. Longer than the longest stride there is
## (sim_stride's far band, 10, times the most relief, 4), so a booking never
## laps itself.
const WHEEL := 64
## How often somebody taken out of the tree is looked at again. The engine does
## not process a node outside the tree, so neither does this — it just keeps
## their place.
const OUT_OF_TREE := 8

static var _the: CrowdClock = null

## WHEEL slots; each holds pairs: a villager, and the frame they were booked
## for. A booking whose frame no longer matches the villager's `_clock_due` was
## superseded — somebody fetched forward leaves their old booking behind, and
## this is how it is told apart.
var _slots: Array = []
## SEATS, handed out in order as people join: 0, 1, 2... A turn falls where
## (frame + seat) % stride is zero, so a town founded in one go is dealt across
## its cycle perfectly evenly — one seat to a frame, round and round.
var _next_seat := 0
var _last := -1       # the last physics frame served
## THIS STEP'S ANSWERS, worked out once for everybody: where the camera is, and
## the stride of each band (Util.band_stride). Asking per villager went through
## three autoloads a time and was most of what the clock itself cost.
var _focus := Vector3.ZERO
var _strides: Array[int] = [1, 1, 1]
var _near_frames := 0


## A NEW VILLAGER JOINS THE CLOCK, from their own `_ready`. Their first turn is
## the first frame their stride gives them, so a town founded in one frame is
## not a town that lives its first turn in one frame.
static func enlist(who: Villager) -> void:
	if _the == null or not is_instance_valid(_the):
		_the = CrowdClock.new()
		_the.name = "CrowdClock"
		# Deferred: whoever is being readied, its parent is busy adding it.
		who.get_tree().root.add_child.call_deferred(_the)
	who._sim_last = Scheduler.now()
	who._clock_seat = _the._next_seat
	_the._next_seat += 1
	_the._book(who, Util.sim_stride(who.global_position))


## HELD, THROWN OR ALIGHT: their next turn is the next frame, whatever they were
## booked for, and every frame after until it is over.
static func heat(who: Villager) -> void:
	if _the != null and is_instance_valid(_the):
		_the._book(who, 1)


## Forget everybody. For a world teardown.
static func clear() -> void:
	if _the != null and is_instance_valid(_the):
		for i in WHEEL:
			_the._slots[i] = []


func _init() -> void:
	_slots.resize(WHEEL)
	for i in WHEEL:
		_slots[i] = []


func _physics_process(_delta: float) -> void:
	Ledger.open(&"CrowdClock")
	var now := Scheduler.now()
	if _last < 0:
		_last = now - 1
	var step := get_physics_process_delta_time()
	_focus = GameState.camera_focus
	for band in 3:
		_strides[band] = Util.band_stride(band)
	_near_frames = 0
	# EVERY FRAME SINCE THE LAST ONE SERVED, not just this one: a pause stops
	# this node and not the physics frame count, and a booking for a frame
	# nobody served must still come round. Past a whole wheel, every slot is
	# due anyway.
	for f in range(maxi(_last + 1, now - WHEEL + 1), now + 1):
		var at := f % WHEEL
		var slot: Array = _slots[at]
		if slot.is_empty():
			continue
		_slots[at] = []
		for i in range(0, slot.size(), 2):
			_serve(slot[i], int(slot[i + 1]), now, step)
	_last = now
	# The near band's census, for everybody served at once — each counted for
	# every frame since they last asked, as asking every frame used to count
	# them. See Crowd.
	if _near_frames > 0:
		Crowd.counted_near(_near_frames)


func _serve(held: Variant, booked: int, now: int, step: float) -> void:
	if not is_instance_valid(held):
		return                          # gone: their bookings go with them
	var who: Villager = held
	if who._clock_due != booked:
		return                          # fetched forward since: see `_slots`
	if booked > now:
		# A slot shared with a frame still to come, met while catching up on a
		# long gap: it keeps its place.
		var keep: Array = _slots[booked % WHEEL]
		keep.append(who)
		keep.append(booked)
		return
	who._clock_due = -1                 # served: whatever books them next wins
	if not who.is_inside_tree():
		_book_at(who, now + OUT_OF_TREE)
		return
	# Counted from when they last ran — which, for anybody held, falling or
	# alight, was the frame before.
	var owed := clampi(now - who._sim_last, 1, Scheduler.MOST_OWED)
	who.take_turn(step, owed)
	Ledger.open(&"CrowdClock")          # the booking is the clock's, not theirs
	if _hot(who):
		_book_at(who, now + 1)
		return
	var at := who.global_position
	var dx := at.x - _focus.x
	var dz := at.z - _focus.z
	var band := Util.sim_band(dx * dx + dz * dz)
	if band == 0:
		_near_frames += mini(owed, Crowd.CENSUS_FRAMES)
	_book(who, _strides[band])


static func _hot(who: Villager) -> bool:
	return who.burning or who.state == Villager.State.HELD \
		or who.state == Villager.State.FALLING or who._agitation.gripped()


## Book their next turn on the first frame from the next one that their stride
## says yes to: (frame + seat) % stride.
func _book(who: Villager, stride: int) -> void:
	var from := maxi(Scheduler.now(), _last) + 1
	var every := clampi(stride, 1, WHEEL - 1)
	_book_at(who, from + posmod(-(from + who._clock_seat), every))


func _book_at(who: Villager, frame: int) -> void:
	var due := who._clock_due
	if due > _last and due <= frame:
		return                          # already due sooner, and not yet served
	who._clock_due = frame
	var slot: Array = _slots[frame % WHEEL]
	slot.append(who)
	slot.append(frame)
