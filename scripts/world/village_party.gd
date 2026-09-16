class_name VillageParty
extends RefCounted
## THE EXPEDITION, AND WHAT IT TURNS OUT TO BE.
##
## A town that goes out to the herds can come back with meat or with livestock,
## and which of the two was a thing each villager decided alone: the hungry ones
## scored a hunt, the good ones scored a taming, and whichever number happened
## to be larger that second won. So a village never went out — fifty people each
## went out, and the decision was arithmetic rather than anybody's.
##
## It is one job now. A party musters at the totem, and WHO TURNS UP DECIDES
## WHAT IT IS. Two saints in the muster and it is a herding party: they go and
## bring flock home, and whatever hunt the town was minded to is simply off.
## Fewer than that and it is a hunt.
##
## Nothing new governs this. The job board still scores one job and the crowd
## penalty still shares it out; the party only reads the people the board
## happened to send, which is the point — a town's means follow from its
## character without anybody having to consult its character.

## How long a party will stand about waiting for others before setting off with
## whoever came, and how many it will take.
## THE MUSTER WAITS FOR PEOPLE TO STOP ARRIVING, not for a fixed twelve seconds
## from whenever the first one turned up. The clock was started once, by the
## first joiner, and ran out while others were still walking over — so a party
## that a whole town wanted to join left with whoever happened to be standing
## there when it expired, which is why banding up never felt like banding up.
##
## Every arrival now pushes it back. The band leaves when nobody has joined for
## MUSTER_SECONDS, or when it is twenty strong and there is no more room — and
## twenty is a real crowd, which is the point. Bringing down something big is
## supposed to be the thing a village does TOGETHER.
const MUSTER_SECONDS := 10.0
const PARTY_MOST := 20
const PARTY_LEAST := 2
## How many of the saintly it takes to turn a hunt into a drive. Two is enough
## to argue a small party round; it is a minority, deliberately, because a
## conscience that only works when it is already the majority is not doing
## anything.
const SAINTS_TURN := 2
## What counts as saintly. The same line the hover text draws when it calls
## somebody saintly, so what the player reads and what the party counts agree.
const SAINTLY := 60.0

## "" while the party is still gathering; then "hunt" or "herd".
var means := ""
## What they settled on going after. One quarry for the whole party — a hunt is
## the one job in this village where converging on a single point is the
## correct behaviour and not a bug.
var game: Animal = null
var flock: Herd = null

var _members: Array[Villager] = []
var _left := 0.0


## Is there room for another, and anything worth going after?
func mustering(town: Village) -> bool:
	if means != "":
		return false
	if _members.size() >= PARTY_MOST:
		return false
	return town.watch.game != null or town.watch.stock != null


func join(who: Villager) -> void:
	if means != "" or _members.has(who):
		return
	# EVERY ARRIVAL PUSHES THE CLOCK BACK. See MUSTER_SECONDS.
	_left = MUSTER_SECONDS
	_members.append(who)


## Has the party made up its mind? Members wait at the muster until it has.
func settled() -> bool:
	return means != ""


## THE MUSTER, ON THE VILLAGE'S OWN CLOCK. It sets off when it is full, or when
## it has waited long enough and has anybody at all.
func muster(delta: float, town: Village) -> void:
	_prune()
	if means != "":
		# Home again — or dead, or wandered off. Either way the party is over
		# and the next one can form.
		if _members.is_empty():
			stand_down()
		return
	if _members.is_empty():
		return
	_left -= delta
	if _members.size() < PARTY_MOST and _left > 0.0:
		return
	if _members.size() < PARTY_LEAST and _left > 0.0:
		return
	_decide(town)


## WHO TURNED UP, AND SO WHAT THIS IS.
func _decide(town: Village) -> void:
	var saints := 0
	for v in _members:
		if v.morality >= SAINTLY:
			saints += 1
	var herd := town.watch.stock
	var prey := town.watch.game
	if saints >= SAINTS_TURN and herd != null and is_instance_valid(herd) \
			and town.tamed_count() < Workshop.stalls(town):
		means = "herd"
		flock = herd
		if town.is_player_home:
			GameState.announce(
				"%d of the %s party would not hunt. They go to bring the %s home."
				% [saints, town.village_name, herd.species])
		return
	if prey != null and is_instance_valid(prey):
		means = "hunt"
		game = prey
		return
	# Nothing left worth going after between deciding to go and going.
	stand_down()


func stand_down() -> void:
	means = ""
	game = null
	flock = null
	_members.clear()


## A villager has finished with the party, one way or another.
func leave(who: Villager) -> void:
	_members.erase(who)


func size() -> int:
	return _members.size()


func _prune() -> void:
	var kept: Array[Villager] = []
	for v in _members:
		if is_instance_valid(v) and not v.is_dying():
			kept.append(v)
	_members = kept
