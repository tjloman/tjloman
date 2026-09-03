# Hand of the Heavens (working title)

A ground-up, **Black & White**-inspired god game built in Godot. You are a
divine hand over a living world: villagers with real needs and desires, a
creature that learns, belief as your currency, and miracles cast with mouse
gestures.

This is the **ugly proof of concept** stage. Everything is primitive shapes on
purpose — we are building *systems first, art later*.

## Requirements

- **Godot 4.7-stable** — https://godotengine.org/download
  - ⚠️ Everyone on the team uses this exact version. When we upgrade, we all
    upgrade in one commit.
- Git

No other dependencies. No plugins, no assets to download — the whole world is
generated from code.

### Validating changes without running the game

```
gdparse scripts/**/*.gd          # syntax
gdlint scripts/                  # style
python3 tools/check_calls.py     # calls to methods that DON'T EXIST
```

That last one matters: `gdparse` only checks syntax and `gdlint` only checks
style, so a call to a method that was never written passes both and then
crashes the moment that code path runs. Every rule in `check_calls.py` is there
because it shipped a broken build at least once:

- **`ClassName.foo()` and `(x as ClassName).foo()`** — resolved against what
  each `class_name` script really declares, following `extends`, and through
  dotted chains (`wronged.mind.judge(...)`) so a bad call two levels down is
  still caught.
- **Wrong argument types and counts**, against the real signature.
- **`_helper()` on self** — delete or rename a private helper and every call to
  it still parses and still lints. Restricted to underscore names, which are
  ours by convention; an unprefixed bare call could be any of hundreds of
  engine methods.
- **Invalid string escapes** — a stray `\` in help text is a *parse* error that
  gdparse accepts and Godot does not.
- **Redeclared variables**, tracked by indentation, since GDScript rejects a
  second `var x` while the first is still in scope.
- **`"a" + "b" % [args]`** — `%` binds tighter than `+`, so only the last piece
  gets formatted.
- **A typed array assigned from `filter()`/`map()`/`slice()`** — those return a
  plain `Array`, which will not go into an `Array[T]`. It fails on the frame
  that line first runs, so it reaches players. Use `Util.prune()` or a loop.
- **A `:=` inferring Variant** from `pop_back()`, `front()`, `get()` and
  friends, which this project builds as an *error* — one such line stops every
  dependent script loading.
- **A local or parameter named after a base-class property** — `scale` in a
  `Control`, `basis` in a `Node3D`, `show` as a parameter. Godot warns and the
  build still runs, so these reach the player as log noise; worse, the next
  edit that means the node's own `scale` silently gets the local instead.
  Three have shipped, which is what earned the rule.

The last three share a shape worth internalising: **Godot rejects it, gdparse
does not.** Syntax checking cannot see any of them.

### That `text_edit.cpp` gutter error spam

If your log fills with hundreds of lines like

```
scene/gui/text_edit.cpp:6981 - Index p_gutter = -1 is out of bounds (gutters.size() = 4).
```

**it is not this project.** It is a long-standing Godot editor bug
([#81135](https://github.com/godotengine/godot/issues/81135), earlier
[#58075](https://github.com/godotengine/godot/issues/58075)): the script editor
calls `set_line_gutter_item_color()` with `line_number_gutter`, whose default
value is `-1`, before the gutter indexes have been resolved. It fires **once
per line it tries to colour**, which is why the count runs to four figures.

Nothing here can cause it — the project contains no `TextEdit` or `CodeEdit`
at all (the one `LineEdit`, in the profile menu, is a different class with no
gutters), and no editor plugins. It also comes from `editor/` code, which is
not compiled into export templates, so **an exported build never prints it**.

To stop it: **Editor Settings → Text Editor → Appearance → Gutters →
Highlight Type Safe Lines → off.** Closing open script tabs before running also
works. It shows up most in setups with an external editor attached (the
`Debug adapter server` / `GDScript language server` lines in your log), and it
hits this project harder than most for an ironic reason: that setting colours
statically-typed lines, and nearly every line here is statically typed.

## Getting started

1. Clone the repo.
2. Open Godot → **Import** → select `project.godot` in the repo root.
3. Press **F5** (Run Project).

### Linux note (incl. ShaniOS / immutable distros)

The Godot editor is a single portable binary — keep it in `~/Apps/godot` and
you're done. No system install required.

## Controls

| Input | Action |
|---|---|
| Left mouse on land (drag) | Grab and drag the world (B&W style) |
| Left mouse on things | Pick up food / villagers / animals — even **trees** (uproot any; gentle drop replants, hard throw splinters, dropped on a storehouse banks full lumber; your creature uproots trees smaller than itself) |
| Gentle release **at your creature** | **Hand it the object** — innate; raises its attention and bond |
| Throw **to your creature** | With attention and practice it **catches** — praise catches to train the skill |
| Release with a **still** hand | **Place gently** — no fear, no harm. Placing a villager in another village makes them a **missionary** (yours → heathen town) or a **convert** (anyone → a faithful town) |
| Release while moving mouse | Throw — your hand's momentum carries; flick hard to hurl far |
| **Hold right mouse + draw** | **Cast** — opens the casting session; one stroke is one rune; stop and it casts |
| Mouse wheel | Zoom |
| Middle mouse drag | Rotate / tilt camera (tilts above the horizon for skyward throws) |
| WASD / arrows | Pan camera |
| Q / E | Rotate camera |
| 1 / 2 / 3 / 4 | Village diet: Vegan / Omnivore / Carnivore / Cannibal |
| P / L (hand near creature) | **Pet** (reward) / **scold** (discourage) its last deed |
| G | **Lead your creature** to where your hand points — it goes there and waits (G again releases) |
| C | **Lock** the camera onto your creature — centered, orbitable; C again (or pan) releases |
| V | **Villages roster** — list your faithful villages (population, distance) and **snap the camera** to any of them |
| F1 | Help panel |
| F3 | **Workshop** — save, load, regenerate the world, new game, replay the lessons, and a few test cheats |
| F4 | Skip the opening lessons |

### Miracles — open the casting, then draw runes

Casting is a thing you deliberately **enter**. Trying to tell a drawing from a
drag moment by moment does not work on a touchscreen: every scheme for it either
steals your pans or misses your strokes, and one of them cast a half-finished
working out of the player's hand mid-stroke. So:

| | |
|---|---|
| **Open it** | Hold the **right mouse button** · or on touch, press bare ground and **hold** — a ring fills under your finger |
| **While open** | **The world is held.** Nothing pans, nothing is picked up, and *every stroke is a rune* — there is nothing left to disambiguate |
| **Close it** | Just **stop**. After a couple of quiet seconds what you drew is cast; if you drew nothing, you are simply let go. Escape leaves at once |

The bar along the bottom is the time remaining, and it **only runs down while
you are not drawing** — so you may take as long as you like over a single rune.

**One unbroken stroke is one rune.** Lift and draw again to add another to the
same working.

| Shape | Rune | | Shape | Rune |
|---|---|---|---|---|
| `S` or `~` | **water** | | tall line | **force** |
| flat line | **earth** | | diagonal | **fire** |
| `O` circle | **life** | | spiral | **air** |
| reverse spiral | **calm** | | zigzag (3–7 teeth) | **fury** |
| `^` caret | **sky** | | bow / arc | **ward** |

Three rules do all the work:

**1. One rune alone is its plainest form.** Water is rain, force is lightning,
life is food, calm is a healing.

**2. The same rune again makes it BIGGER, not twice.** Water is a sprinkle;
water-water a cloudburst; water-water-water a deluge.

**3. Different runes make a third thing.**

| Drawing | Miracle |
|---|---|
| water + force | **Thunderstorm** — rain, and strikes falling through it |
| water + force + force | **Lightning storm** |
| water + force + force + fury | **Tempest** |
| air + air | **Tornado** |
| air + air + water | **Hurricane** — the whole sky at once |
| air + fire | **Firestorm** — the wind spreads the burning |
| earth + life | Forest · life + water | Forage thicket |
| air + calm | Flight · air + earth | Portal |
| earth + ward | Strength · life + sky | Bird flock |

**And anything else still works.** A combination nobody named casts every rune's
own miracle at once, each a little weaker — of the 285 distinct drawings of
three runes or fewer, **zero** mean nothing.

#### How the shapes are actually recognised

By **template matching** (the `$1` recognizer family), not by heuristics. The
first version measured turning, corners and straightness, and it failed in play
for a reason worth writing down: those measurements survive *uncorrelated*
noise, which is what a test harness produces, but **a real hand does not shake
randomly — it wobbles**, slowly and smoothly, and a slow wobble reads as genuine
curvature no matter how much you smooth it. Carets were coming out as waves —
water — rain, about half the time.

Every stroke is now resampled to 48 points, centred, scaled, and compared to
reference drawings; nearest wins, or nothing does. Two departures from the
published algorithm, both because these gestures are not abstract symbols:
**no rotation normalisation** (a vertical and a horizontal line are different
runes — orientation is meaning) and **uniform scaling** rather than into a
square (which would likewise make a tall line and a wide line identical).

Measured against simulated hand tremor: **the heuristics read carets 3 times in
8; the template matcher reads every shape correctly**, and holds at 100% through
heavy tremor, ten-sample flicks, and strokes from a third to two and a half
times normal size. Scribbles and pokes are still rejected.

Adding a gesture is now adding a template, not inventing another measurement
that must avoid colliding with all the previous ones.

Where a shape has a free PARAMETER, every plausible value of it needs a
template too, and this has bitten three times now. Spirals matched nothing
until the turn count was offered as a range (1½ to 3). Zigzags worked at
*exactly five teeth* and read as a straight line at three, four, six or seven —
which is force, or earth — so **fury was very nearly uncastable**. Point-wise
distance is merciless about parameters nobody consciously chooses.

The price of dropping rotation invariance is that **every bearing must be a
template of its own**, and forgetting that is not academic: waves and zigzags
were supplied lying down only, so an `S` written the way people actually write
the letter — tall, or on the slant — read as a diagonal slash. Which is fire.
Which meant **water could not be cast at all**. Each shape now carries every
orientation it can plausibly be drawn in, and the smoke test draws each of them
upright, lying down and slanted.

**Your dominion is your spellbook**, and villages teach **runes**, not finished
miracles. Every combination of the runes you hold is yours for free, so learning
rain and lightning apart *is* how you come to hold the storm.

| Villages | Rudiments taught | Named miracles castable |
|---|---|---|
| 1 | water · life · calm | 6 |
| 2 | earth · force · ward | 11 |
| 3 | fire · sky | 13 |
| 4 | air · fury | 21 |

**Portals** are cast in **pairs**: the first gate hangs open and waiting, the
second links to it — and from then on villagers, livestock, your creature and
anything you throw can step through and cross the world. **Flight** lifts your
creature into the air, where it soars over water, wood and hill alike.

The mightiest workings also need a **wide reservoir of prayer** — each converted
village raises your cap (+120) and widens the fury of storms and flocks.
Everything you conjure is a throwable you place where you choose.

## The world

- **Simulation LOD, honestly paid for**: villagers and beasts far from the
  camera run on a slower clock, updated every few frames with the skipped time
  folded into `delta`. The catch — and it cost two playtests — is that
  `move_and_slide()` integrates over the **engine's** frame, not the delta you
  hand it, so a throttled body silently walked at a quarter or a *tenth* speed
  while its hunger ticked at full rate. Distant villages starved on the way to
  the granary. The stride is now folded into velocity as well as into time.
- **Endless, chunked terrain**: 48m chunks stream in around the camera.
  Elevation from layered noise, lakes below the water table, and five
  biomes — grassland, forest, savanna, rocky hills, wetland — each with
  its own colors, trees, and wildlife. Everything is deterministic from
  the world seed.
- **Neutral villages** generate out in the world. They run the full
  simulation (farming, building, families) but believe in nothing until
  your miracles convert them (belief ≥ 40) — then their prayers feed you.
- **Day/night cycle**: ~5⅓ real minutes per day. Sun, moon, dawn/dusk
  skies. Villagers sleep at night; house windows glow; wolves prowl —
  preferring villages gone wicked. A villager's whole life spans about
  **40 days** — time enough to grow up, raise a family, and grow old.
- **Fire spreads** — and is contained by default. Lightning (and its
  storm) and fireballs set trees ablaze; a blaze leaps only to close
  neighbours and burns out in seconds, so it runs through a dense stand
  and gutters out at gaps and water — a **tool for clearing forest that
  would otherwise creep across the map**. Rain douses it; a thrown
  burning tree is a firebrand. Fire scares off villagers and beasts but
  spares buildings.
- **Water is real**: villagers and animals cannot cross it (frogs
  excepted); nothing builds beneath it. The **shoreline feeds**: villagers
  and the creature go **fishing** — fish counts as meat, with its own
  silvery model. The creature **wades** at half speed (a future miracle
  will let it walk on water).
- **The world is the interface**: each village's ring shows its
  **population as size** and **belief as color** (gray → gold; converted
  rings wear your alignment color); the totem orb **glows with prayer
  power**. Hover a house for the census, a farm for harvest progress, the
  storehouse for stocks. **Grab a quarter of the storehouse** to withdraw
  that resource as a physical item; drop food/lumber/stone onto any
  storehouse to bank it.
- **A living ecology**: wild animals have hunger and thirst — they trek
  to water to drink, browse forage bushes, graze, breed when fed and
  watered, and die of old age way out in the woods. Forage bushes with
  regrowing berries dot every biome (villagers forage them too when the
  granary runs dry). Trees grow from 1-lumber saplings to 30-lumber
  giants — the model scales with maturity. **Woods do not swallow the map**:
  growth is a lottery (a tree only *might* thicken on any given tick), only a
  **fully grown** tree drops seed, and crowding cuts both the growing and the
  seeding odds — so a stand thins at its own edges and creeps instead of
  marching. Rock deposits hold 300 stone and visibly wear down.
- **Sound**: every sound is synthesized in code at startup (no assets) and
  played positionally — bleating, clucking, sawing, quarry picks, hammers,
  worship murmur, barks, howls, frog croaks, and the boom of a fireball.
- **Rendering**: the Mobile renderer + MSAA. Good and plain — meant to look
  right on a phone, no advanced GPU required (yet).

## Its character is a compass, not a wire

Every god game before this one ran its creature down a single wire from GOOD to
EVIL, so every beast ever raised sat somewhere on one line and the only question
left was how far along it got. That line throws away almost everything worth
knowing about a character: the beast that tends fields, the one that dances for
the villagers and the one that hauls stone home all read as "gentle".

Character here is a **point in six dimensions**, each a running impression of
what the creature has lately been doing:

| | | |
|---|---|---|
| **mercy** ↔ cruelty | how it treats things that can suffer | *carries moral weight* |
| **bounty** ↔ appetite | whether it produces or consumes | *carries moral weight* |
| **order** ↔ ruin | whether it builds up or breaks down | *carries moral weight* |
| **fellowship** ↔ solitude | whether it seeks people or gets away from them | flavour |
| **daring** ↔ caution | what it does about risk | flavour |
| **devotion** ↔ wilfulness | what it does about **you** | flavour |

Only the first three carry any good and evil at all. The other three are pure
flavour, **and flavour is the point**: a creature can be a *tender wrecker*, a
*ravenous disciple*, a *bold recluse*, a *cruel provider*. Simulating four
thousand random lives gives **383 distinct readings**, and **169 different
characters all sitting at good/evil zero** — the fifty flavours of neutrality
this was built for, three times over. Sixteen pairings earn a name of their own
once both leanings are firmly held: *man-eater*, *beloved of the village*,
*better than its god*, *force of nature*, *your instrument*.

**Conscience runs on all six axes.** A creature that has grown SOLITARY finds
holding court before the village genuinely unpleasant though nothing about it is
cruel; a WILFUL one finds copying you distasteful without being wicked. Neither
refusal was expressible on a wire.

Nothing here chooses anything. The compass only reads what deeds *mean*, and
that meaning then feeds back into what the creature finds congenial — which is
how a character sticks without a single rule saying "be a wrecker".

## What it feels, and how it reads other people

Mood was one number from wretched to delighted. A number cannot be frightened
**and** lonely, cannot be ashamed while it is also proud of something, and above
all **cannot be read off somebody else**.

Its heart holds **thirteen named feelings at once**, each cooling at its own
rate — fury is gone in seventeen seconds, grief lasts four minutes, loneliness
seven and only really lifts when somebody turns up. The strongest drives its
face and the word over its head, so a beast carrying last night's grief looks
like it while it goes about its business. Mood is now downstream of feeling
rather than a second set of books.

**Empathy has to be paid for in experience.** Every few seconds the creature
notes which feelings it is holding and which circumstances are true at the time,
and slowly builds up an account of what being hungry, hurt or alone in the dark
is actually like — *for it*. Nothing is written down in advance. Reading
somebody else is then that same account applied to their plight, described in
exactly the same vocabulary. So:

| The creature | reads a starving man as | and feels |
|---|---|---|
| has never suffered | nothing at all | nothing |
| has starved itself | in pain, and friendless | **pity** |
| was raised among joy (reading a *happy* villager) | delighted | **delight** |
| was beaten near the village (same happy villager) | full of dread | **pity** |

It is not a sensor. It is a creature guessing about other people out of its own
history, and it is wrong in exactly the ways that history makes it wrong.

There is a deed to go with it: **soothe** — walk over to whoever nearby is worst
off and simply *be there*. No carrying, no miracle. They steady, and it feels
the comfort it gives, which is the loop that makes a comforted creature grow up
comforting. Whether it ever takes that option is entirely its own affair.

## The crowd mind

A village used to be a hundred people each independently noticing a god. That is
both wrong about crowds and ruinously expensive — every villager scanning for
the creature sixty times a second is exactly what stops this holding a thousand
of them.

Now **the town thinks once**. It holds five feelings (awe, terror, anger, joy,
sorrow), what the crowd is looking at, and what it is minded to do, recomputed
about twice a second for the whole settlement. Villagers read those few numbers
in their own decision — a dictionary lookup and a dice roll, no scanning — so
responding to you costs the same whether the village holds twenty people or a
thousand.

**The grip is never total.** Each villager rolls privately against the share of
the town the mood has swept up, so a crowd half-mad with awe still has people
getting the harvest in.

| What the town saw | What it does |
|---|---|
| rain overhead | **watches** |
| a second wonder | **adores** |
| fire from the sky | **scatters** |
| the creature in the granary, once | takes it as an outrage |
| ...and again, and again | **takes up arms** |
| a funeral | **mourns** |
| the creature dancing | **comes and joins in** |

That last one closes a loop nobody wrote. The creature can only dance because it
watched villagers dance; once it can, its dancing is an **invitation** — not a
summons — and a town that is not frightened of it comes and takes part. Which
puts the creature in the middle of a crowd of people dancing and praying, which
is precisely the thing it learns dancing and praying by watching. A village that
is frightened of the beast declines, and it dances alone.

## Getting anywhere

Local steering is a bug algorithm: it flows around a trunk beautifully and walks
straight into a bay, a horseshoe ridge or a cliff-backed cove and stays there
until a watchdog gives up. From outside that reads as a stupid animal, and no
amount of cleverness in its head fixes it.

Anything more than a short hop is now **routed** — a bounded A* over a coarse
grid costed from the land itself: water depth, the rise between cells, how thick
the standing timber is. The terrain half of that cost is cached for the whole
session (the world comes from a seed; a hillside is the same hillside all game),
so the hundredth crossing of a valley is nearly free. The search is capped, and a
search that runs out simply returns nothing and the creature walks the old way —
routing can never make it worse than it was.

**And it learns the landscape.** Every spot it gets properly stuck in is written
down and priced into every route it plans afterwards, so a creature that has
wedged itself in the same gully twice starts going round it. The memory fades —
a gully choked with fallen timber in spring is walkable by autumn — and it
survives a save, because it was earned.

## What your creature BELIEVES

Its learned action-values answer *"is this worth doing?"*. Its **beliefs**
answer the far more interesting question — ***"worth doing when?"*** — and this
is what makes one creature genuinely a different person from another.

- **Episodes.** Every deed is remembered with the **circumstances** around it.
  Not "I ate a villager" but "I was starving, in their village, at night, with
  armed men about, and my god was nowhere near."
- **Credit.** Consequences arrive *late*. When a mob drives it off, or its god
  praises it, or it is wounded, the blame is spread back over the deeds that
  led up to it. **Nothing tells it that being chased comes from eating people**
  — it works that out because being chased keeps following having eaten one.
- **Contextual weights.** Each action carries a small learned model over the
  circumstances, so the lesson attaches to the *situation*, not the deed alone.
- **Lore — what the world does on its own.** Separately from blaming its own
  deeds, it notes that *this sort of thing happens in this sort of moment*.
  After a run of bad nights it holds "nights end in pain", "beasts about end in
  pain", "the village is where it is cheered" — and a night alone with wolves
  around reads as a bad moment **before it has done anything at all**, which
  leans it toward getting away and away from making its own excitement. A
  creature that can only explain the world through its own agency has a very
  small world.
- **Places.** A memory of *ground*, in eighteen-metre patches. The wood where it
  kept coming off worst ends up hated and home ends up loved, and that colours
  everything it might do while standing there. It is not told which places
  matter; it simply keeps getting hurt in the same stretch of country.
- **Recall.** It holds four hundred moments — most of an afternoon rather than
  two minutes — each with **where** it happened and **how it felt**. When the
  present closely resembles a strongly-felt past, especially standing in the
  very spot, a shadow of the old feeling comes back. It is a whisper, so
  standing somewhere awful builds dread over half a minute instead of flooring
  the beast the instant it arrives. **It will never be able to say why it does
  not like it here.**
- **People, by name.** Everything above is about *kinds* — villagers, sheep,
  houses — which is right for a mind that has to generalise. But a dog knows
  *who you are*. A separate ledger holds a few hundred **individuals**, and
  every dealing nudges its regard for **them**, so a creature can adore one
  shepherd and give another a wide berth while holding no opinion whatever
  about shepherds.

The result is that the **same act teaches opposite lessons** depending on what
actually follows it:

| What happens after it eats a villager | What it comes to believe |
|---|---|
| The village mobs it | Recoils from crowds — but will still take a **lone** shepherd |
| You kill the mob and praise it | **Unrepentant.** It learns to stand its ground |
| The villagers flee and hide | Terror **works**. A tyrant is born |

**Villages learn too.** They do not only fight back. A village that stands and
wins grows **resolve**; one that buries its dead **loses its nerve and hides
indoors instead** — so one settlement becomes a militia and its neighbour a
people who bar their doors, out of their own history rather than any rule. And
a village that hides is the very thing that teaches your creature that terror
pays.

Lock onto your creature (**C**) and the dashboard tells you what it currently
believes, in plain words.

## It grows for thirty hours, not for one

Growth used to be a percentage, and a percentage is a terrible unit for a life:
it ran out. A well-fed creature crossed the whole arc in about **an hour and a
quarter** and then had nowhere left to go — both an anticlimax and a waste of
the most legible reward the game has.

It now has **STATURE**: a number from 1 to **65,535** (`0xFFFF`), which is the
readout on the dashboard in decimal and in hex. It moves every time the creature
digests something, so there is nearly always a little more of it than there was,
and it is a long way from the top for a very long time.

Two rules keep the arc honest:

- **Only food the body actually WANTED counts.** Surplus goes to fat and buys no
  stature at all, so a creature cannot be force-fed up the arc faster than it can
  get hungry.
- **Size is the SQUARE ROOT of stature.** The early climb is visible — a
  hatchling is a different animal within the hour — and the last stretch to a
  tower over the treetops is the work of many sessions.

| Played | Stature | | Size | Height | Stomach | Energy pool |
|---|---|---|---|---|---|---|
| newborn | 1 | `0001` | 0% | 2.9m | 2.1 units | 101 |
| 1 hour | 2,215 | `08A7` | 18% | 9.1m | 5.7 units | 151 |
| 4 hours | 8,861 | `229D` | 36% | 15.5m | 9.4 units | 203 |
| 8 hours | 17,723 | `453B` | 52% | 20.8m | 12.4 units | 246 |
| 15 hours | 33,230 | `81CE` | 71% | 27.5m | 16.2 units | 299 |
| 30 hours | 65,535 | `FFFF` | 100% | 37.5m | 22.0 units | 380 |

(a villager is about 1.8m; a full-grown tree about 30m)

The 0–1 `growth` number everything else reads — the size of its stomach, what it
can lift, how much it can spend on a miracle, how fast it walks — still means
*how far along its SIZE it is*, not how far along its whole life. That is what
lets a thirty-hour arc drop in under a body balanced for a one-hour one without
retuning a single other number. An old save's `growth` finds its own place on
the new scale.

## Your creature's body

It does not simply eat and grow. It has a **real stomach** whose size follows
its own: a chicken half-fills a hatchling, and a hatchling **cannot finish a
cow** — it swallows what fits and leaves the rest. Food then **digests over
time** (about 45 seconds for a hatchling's bellyful, ~100 for a grown beast's),
and where it goes depends on whether the body wanted it:

- **hungry** → nourishment, and a little growth
- **not hungry** → **fat**

Fat makes it slow, heavy and disinclined to exert itself — and a lazy creature
only gets fatter, because work is what burns it off. **Muscle** is the mirror
image: it comes from *exertion* (hauling, smashing, running), decays when
unused, and decides **what it can lift**. A hatchling wrestles saplings; only a
grown, well-worked beast can uproot a forest giant. The **Strength** miracle
(NATURE, `~`) lends it a giant's grip for a while, enough to carry trees far
beyond its own muscle — a loan against strength it hasn't earned.

Watch all of it in the creature dashboard (lock on with **C**): belly fullness,
whether it's digesting, and whether it's *lean*, *sturdy*, *powerful*, *fat*
or *obese*.

## The core loop (what's simulated)

- **Villagers live whole lives**: they age, come of age at 16, slow down
  as elders, and die at 60–85 (about 40 day/night cycles) — leaving a
  physical **corpse**. Adults courting at the totem conceive children;
  pregnancy lasts nine months (game time), then a child is born, plays
  instead of working, and grows up. Births are bounded by shelter —
  build houses to grow the flock.
- **Jobs are chosen, not assigned**: every adult scores what the village
  lacks — food, lumber, stone, housing, repairs, livestock — and takes the
  most urgent work: farming, hunting, felling timber, quarrying, building,
  taming. Choices are **pooled and spread** — a job the flock is already
  crowding onto is discouraged, so villagers fan out across the village's
  needs instead of conga-lining to one resource. Starvation is lethal —
  and the god who allowed it is judged.
- **Villages grow where you tend them**: a village left alone barely
  multiplies — conception is slow by default. **Divine attention** quickens a
  people: miracles cast over them, your hand setting someone down among them,
  your creature working in their fields. Attention fades over a minute or so,
  so a kingdom expands where you actually *spend time*, not everywhere at
  once. Hover a village to read whether it is thriving or merely quiet.
- **The militia — villagers fight back**: predators no longer farm defenceless
  people. When one villager is hurt, the whole village is ROUSED: the able
  arm themselves at the storehouse (club · spear · bow · sword, paid for in
  lumber and stone — they make the best they can afford) and go for the
  threat. Courage comes from NUMBERS: a villager caught **alone** will not
  stand — they run, and a wolf usually runs them down. Two or three together
  turn and kill it. If a villager **dies**, the village swears a blood debt
  against that specific beast and hunts it wherever it goes, and clears any
  predator inside its bounds. Hurt (or eat) their people with your creature
  and their **grudge** grows — push it far enough and they will take up arms
  against your creature too, wounding it and driving it off. A creature hurt
  this way learns to fear them.
- **Nothing teleports**: a gathered catch, harvest, timber, or stone must be
  **carried home on foot** to the storehouse (you can see the load in their
  hands) before it counts. A load abandoned in fright is dropped and lost.
- **Houses are mortal too**: hut / house / longhouse (sleeps 2/4/6), each
  with health and age. A **lived-in house is a kept house** — only empty
  ones decay with age and collapse. Builders raise new ones (lumber +
  stone, placement checked for slope, water, and clearance) and repair
  old ones. The homeless sleep rough by the totem, recover poorly, and
  grow miserable. Villagers also **break new fields** when the village
  goes hungry, and **feed the penned livestock** from the granary; the
  pen has a **well** so tamed animals can drink.
- **Livestock and taming, gated by virtue**: benevolent villagers tame
  horses (ridden on long trips), oxen and llamas (hauling: +1 to every
  harvest), and dogs (guarding, herding, and ambient joy). Wolves avoid
  villages with dogs. Monstrous villages can't tame — they abandon
  agriculture entirely, hunt, and butcher whatever is in the pen.
- **Wild things**: deer, bears, wolves and tigers in the forests; lions,
  giraffes and llamas on the savanna; frogs in the wetlands. Predators
  hunt prey — and occasionally people.
- **Diet is policy** (keys 1–4): Vegan (plants only), Omnivore, Carnivore
  (hunt the sheep), or **Cannibal** — corpses are butchered for the granary.
  Eating human flesh corrodes a villager's soul; the good refuse until
  starvation breaks them.
- **Three karma systems, kept separate**:
  - **Player alignment** (−100…+100): moved by your miracles, throws, and
    what you let happen. There is no bar: **your hand is the gauge**,
    shifting gold to blood-red — and **the sky itself is your
    conscience**, gilding warm for the saintly, bruising ash-and-blood
    for the monstrous. Converted village rings wear the same color.
  - **Creature morality**: independent. It drifts with what the creature
    *witnesses* you do — and with what you praise. A gentle creature tends
    the farm; a vicious one eats corpses; a monstrous one hunts your own
    villagers when hungry.
- **The creature observes, learns, and feels.** It has mood, boredom, and
  a bond with your hand. It *watches* villagers work and grows curious
  about their jobs; its desires (tending, hauling food to the granary,
  playing, guarding at night, mischief) are learned weights you shape by
  petting (P) or scolding (L) its last deed — praise cruelty and you are
  raising a monster. It plays with the sheep, dances for the children,
  spooks villagers when bored and mean, and sulks when told off. Hover it
  to read its heart; press C when you lose track of it.
  - **Villager morality**: shaped by diet, trauma witnessed, and worship.
    A virtuous flock prays with more conviction (more prayer power).
- **Belief** rises when villagers witness miracles — kindness or terror both
  work. It widens your **sphere of influence** and raises max prayer power.
- **Lightning is lethal** at the point of impact. The evil path is real.
- **Sheep** wander, breed slowly, get hunted, and are 100% throwable.

## Weather that looks like weather

A rain cloud used to be five bulbous spheres that snapped into existence, sat
perfectly still for twelve seconds, and snapped out again. It read as five grey
balls, because that is what it was.

It is now a **swirl of soft streaked sheets** — wide flat patches of vapour
lying in the sky, each of which **turns** at its own rate and direction so the
mass shears against itself, **breathes** in and out of phase with its
neighbours so it billows rather than merely rotating, and **comes and goes**:
fading in somewhere, holding, fading out, and being reborn elsewhere. The cloud
is never twice the same cloud, and nothing in the sky ever pops — the mass
gathers when it is cast and disperses when it is done.

**Definition comes from overlap.** One sheet is a vague smudge; a dozen
overlapping at different angles, heights and opacities have edges, depth and
shape. So severity is simply *how many*:

| Working | Sheets | Mass | Layers deep | Opacity | Look |
|---|---|---|---|---|---|
| rain | 7 | 18m | 3.7× | 50% | pale |
| cloudburst | 13 | 24m | 4.5× | 66% | grey |
| tempest | 16 | 27m | 5.0× | 75% | grey |
| deluge | 22 | 32m | 5.5× | 90% | bruised |

Those opacities are the second pass. The first ran a shower at 28% and a deluge
at 46%, which on a bright sky read as haze rather than weather — a quarter-solid
sheet is very nearly nothing, and seven of them is still very nearly nothing. A
deluge is now all but solid, which is what lets it darken the ground under it.

The whole cloud is **one draw call**. A MultiMesh carries every sheet with its
own transform and its own colour — per-instance alpha is what lets each fade
independently — and a sheet is a single quad. A deluge's twenty-two layers come
to **44 triangles**, against 1,440 for the five spheres it replaces, in one
draw instead of five.

The real cost is **fill rate**, not geometry: stacked soft transparent quads
are overdraw, which is what a tiled mobile GPU minds most. So the density is
worked out rather than eyeballed (the first pass had a deluge *thinner* than a
drizzle), and the sheet count runs through the graphics budget — and therefore
through the thermal band, so a struggling phone gets a two-layer-deep cloud
either way.

The vapour texture is drawn in code like everything else here: a soft
elliptical falloff multiplied by noise sampled with a squashed vertical, so the
detail runs in horizontal **streaks** rather than reading as a stack of fuzzy
balls. 64×64, built once at world load, shared by every cloud ever cast.

## Land you can wreck

Every hill in this world is derived from the world seed. That is what makes it
endless and what makes it free — nothing about the terrain is stored, because
`WorldGen.height_at()` can work any point out from noise. A world you can only
*look at* needs nothing more.

A world you can **wreck** does. So the ground is now **noise plus a list of
scars** — craters, cones, ripples, basins — and `height_at()` adds them up.

The whole design rests on one thing: **everything that reads the land goes
through that one function.** So a scar propagates for free to the mesh, the
collision, the water table, where villagers are allowed to build, what the
router thinks is walkable, and the colour of the ground. Gouge a hole and the
whole simulation agrees with you a frame later — nothing had to be told.

**The cost has to be nothing**, because `height_at()` is on every hot path in
the game. Three guards, in order:

1. **No scars at all** — one `is_empty()`, and that is the entire call. This is
   an untouched world, which is most worlds most of the time.
2. **Outside everything** — one box test against the union of every scar. In an
   endless world nearly every query is nowhere near the damage.
3. **Actually near one** — only now does it hash into buckets, and only the
   nine around the point, because a scar's reach is capped to one bucket.

Scars are **play, not seed**, so unlike the terrain they go into the save.
Rebuilding is bounded too: a scar re-cuts at most **nine chunks**, and usually
four — mesh, collision, water and everything standing on it, which is set back
down on the new ground. (Living things are left alone; they have gravity and
find the new ground themselves, which looks far better than teleporting.)

### The workings that move the earth

| Runes | Miracle | What it does to the land |
|---|---|---|
| earth + fury | **earthquake** | a ripple of standing waves grows outward in three passes, and everything on it is thrown about |
| earth + fire + fury | **volcano** | raises a mountain with a crater bitten out of its summit, then erupts |
| ward + water | **water walk** | *(no terrain)* the creature crosses lakes at a full stride |
| calm + life + water | **healing shower** | *(no terrain)* ten seconds of green rain that douses every fire and mends what stands in it |

Plus **fireballs now gouge**: a bowl 1.7m deep with a lip of thrown spoil
around it, burned black, and it stays. The old version laid a dark disc on the
ground and faded it out after twenty-five seconds.

These four are **deliberately cheap for now** (20–45 prayer). They are new and
want playing with, and an earthquake priced at two hundred would be cast twice
and never understood. They will be priced properly once it is clear what they
are actually worth. Note that `fury` is a tier-4 rune, so the two earth-movers
need four faithful villages — the F3 workshop's *Convert nearest village* is
the quick way there.

**Two things the simulation caught** that a playthrough would have blamed on
something else. The crater profile was *inverted*: passing a depth of −2m built
a 2m hill ringed by a moat, because the bowl term was already −1 at the centre.
And the first rebuild grew the affected area by a whole chunk on every side,
tripling the cost of every quake to prevent a seam that a metre of slack
already prevents.

## The alphabet, settled

Two glyphs changed and one gesture was added, all three decided by measurement
rather than taste.

**`life` keeps its circle.** It is the alphabet's only closed shape and it does
fail when a hand does not quite close the loop — but every closed replacement
inherits exactly that (an 85%-drawn box reads as a *circle*), and none of the
open shapes carry "a seed, a womb, a gathering". The meaning won.

**`fury` is a sharp Z, not a zigzag.** The zigzag was the one rune that broke
thermally: five teeth need five teeth *sampled*, and a phone that has pulled its
touch scan rate back reports a dozen points for the whole stroke, at which point
they are gone and it reads as a flat line — which is `earth`. On a hot phone
`earth + fury` (the earthquake) was quietly becoming `earth + earth`, which
plants a wood. Two corners survive what five teeth cannot.

**A SWEEP cancels.** Straight down, then hooked away, like brushing something
off a table — the casting session ends and nothing is cast. It is deliberately
**not a rune**: absent from the spellbook, so it can never be an ingredient in a
working or appear in the reference table as one.

Two things were tried for cancel and rejected, both for reasons worth keeping:

- **An X, and a plus.** Both read beautifully — and both are impossible. *You
  cannot lift the finger in this system*, and nobody draws an X without
  lifting. Scoring a retraced X against the alphabet measures whether the
  recognizer can read a motion no hand will ever make. Every candidate is now
  screened for whether the pen ever goes back over its own path.
- **A scribbling-out.** The obvious "erase" gesture, and it collapses to 75%
  under throttling, degrading into `hline` — the identical failure that took the
  zigzag off fury. Many small teeth are precisely what a struggling digitizer
  stops sampling.

**There is far more room than I first claimed.** An earlier pass concluded the
alphabet was "full". That was wrong: it was full of *smooth closed curves*.
Screened for single-stroke shapes only, **ten** clear 100% with high confidence
against the settled alphabet — ell, squared-S, crook, double chevron, J-hook,
squared coil, bolt, wide C, staple, sigma — and they still hold apart when added
all at once. Room for a dozen more runes exists whenever the grammar wants them.

The alphabet now reads at **100% across healthy, warm, hot and throttled
screens, with no fragile rune**, and it costs less than it did: dropping the
zigzag's twenty variants took the reference set from 84 drawings to 50, so every
live reading is about 40% cheaper.

## Casting, felt

Drawing a rune used to be silent and mute: no sound at all, and no reading of
the shape until the finger came up, at which point one line of text appeared at
the bottom of the screen. The most consequential thing in the game was its
quietest and least legible.

**The stroke is read as it is drawn.** Twelve times a second (four on a hot
device — it backs off with the thermal band like everything else), the
half-finished stroke is matched and shown as a glyph underneath it, faint while
ambiguous and firming up as it resolves. A half-drawn circle honestly *is* an
arc, and it is allowed to look undecided; watching it settle is the point.

**Nothing live is ever committed.** The rune that lands on the slate is still
read from the *finished* stroke when the finger lifts. Casting what a shape
looked like on the way past would be indefensible, and the two paths are
deliberately separate functions — `peek` for the picture, `classify` for the
commitment.

**The runes already drawn stand above it**, glowing, each breathing on its own
phase so the row never pulses as one block, brightening as the working grows,
with the newest swelling for a moment as it lands. The glyphs are the
*recognizer's own reference drawings*, asked for by name — so what you are
shown cannot drift from what the matcher will actually accept, which a
hand-drawn set of icons certainly would have.

**A drum on every rune**, pitched down and struck harder as the working grows,
so a three-rune miracle is audibly heavier than a one-rune one before anything
has been cast. **Whispers** come and go out past the edge of what you are
doing — placed around the hand at nine to twenty metres, never on it, so they
read as coming from the trees rather than from you. Both are synthesized in
code like every other sound here: the drum is a hard dry knock over a membrane
tone bending down as the skin relaxes, and the whisper is breath pinched into
syllables and bandpassed to sit where speech sits, so the ear insists it almost
understood something.

Two honest notes on the performance of this. Templates are now built at world
load rather than on the first flick of a finger, which removes a real hitch.
The stroke is also thinned as it is captured — a pointer reports every frame it
moves, and a slow rune arrived as six hundred points where forty describe the
same shape — but **measured, that is a 1.1x saving on a normal stroke** and
only reaches 1.5x on a six-second scrawl; it is worth doing because it is free
(recognition is identical, 300/300 either way), not because it was the
bottleneck. The live reading is the genuine new cost, at 0.78ms per match
against 84 reference drawings, which is why it runs on a clock and backs off
when the device is hot.

## Night you can actually see

On a phone, in daylight, night was a black screen. You could not find your own
creature in it. The fix is not a brightness slider — it is giving the dark some
real sources of light and letting the eye read shape by them. There are four,
and only one of them costs anything.

**The moon and the stars.** The moon's fill was 0.22, which is a rumour; it is
now 0.55, with a floor under it that never goes out, because starlight is what
keeps a silhouette readable when nothing else is lit. The night sky itself came
off black (0.03 → 0.07) for a reason that is easy to miss: *the sky is the
ambient source*. A black sky means the world under it gets no bounced light at
all, however many lamps you light.

**The ambient floor.** As the sun goes, the sky hands the ambient over to an
explicit moon-blue, so the dark has a *colour* rather than an absence of one,
and the floor rises from 0.25 to 0.55. Bounced light is a uniform, not a light
— it is free, which is exactly why it does the heavy lifting here and the real
lights stay few.

**Windows and torches.** Houses already lit their panes at dusk. Now anyone
still out after dark carries a flame, and a town at three in the morning reads
as a few lit windows and a watchman rather than a field of dark boxes. These
are **not lights**: there may be a thousand villagers, and a thousand point
lights is not a thing a phone will do. They are additive billboards, all of a
town's in one MultiMesh and so one draw call, re-dealt on a lazy clock and only
while the town is close enough to see. Each flickers on its own phase, so a row
of them does not read as fairy lights.

**Hearths.** The only real lights, and the only thing here that actually pools
light on the ground. The count is **fixed** — 2 / 4 / 6 by graphics tier — and
a small pool follows the camera, handing itself to the nearest towns. Walk
across the map and the same four lights come with you. Add a thousand villages
and the budget does not move. A hearth changing hands fades out and fades in
somewhere else rather than sliding across a field.

**The hand's column of light.** Your hand hovers barely a metre off the
ground, so a lamp *on* it lights a dinner plate. It casts a **shaft from
overhead straight down through itself** instead — the only way to get a fair
pool out of it, and the right image for a god besides. Move your hand across
the land and a **17-metre circle of daylight** moves with it, which is enough
to work a field or find someone by without turning night into day. Night-only,
eased in with the dark: by day the sun does this job better.

**The creature's own radiance.** One omni light on the beast, and the one worth
spending unconditionally, because it is always where you are looking: whatever
else you cannot make out at night, you can always find your creature. It burns
brighter the larger it has grown and brighter still while it is working a
miracle, and its **colour is what it has become** — warm gold for a saint, low
red for a monster, and the plain cold moon-white of something that has not made
up its mind. It eases in at dusk the way an ember comes up.

**Gold, red, or moon-white.** The hand and the creature burn by *the same
palette* (`GameState.divine_light`) and by their *own* alignments, which are
very often not the same alignment — so a single glance at a lit night tells you
that a saintly god has raised a monster. Warm gold one way, low red the other,
and the plain cold moon-white of a soul that has not made up its mind in the
middle. This is deliberately **not** `alignment_color()`, which ramps straight
from red to gold and so paints an undecided soul a muddy orange: fine for
painted flesh, quite wrong for a light.

The whole night therefore costs **at most seven point lights and one spot**,
none of them shadowed, whatever the size of the world — and a device that is
getting hot lets the hearths go out one at a time. What it never drops is the
two you steer by: the light in your hand and the beast you are watching.

## When the device gets hot, the creature looks up at you

Godot exposes **no thermal sensor** on any platform, so nothing here pretends to
read a temperature. It watches its own **frame times** instead, which is both
honest and the thing that actually matters: when a phone's SoC pulls its clocks
back, frames get longer and *stay* longer. A device that has been in a warm hand
for twenty minutes and one that simply has too much on screen both arrive here,
and both want the same answer — do less.

Three bands, and a condition has to hold for **four seconds** before anything
moves, so a chunk streaming in, a scene reload or a tornado is never mistaken
for a hot phone. Simulated against real frame-time traces:

| What the device does | What happens |
|---|---|
| a steady 60fps for five minutes | nothing |
| 60fps with a one-second hitch every 30s | nothing |
| two chunk-streaming stalls | nothing |
| sustained 40fps | eases off after ~5s |
| sustained 28fps | eases right off after ~5s |
| 28fps, then recovers | steps back up one band at a time |
| hovering right on the threshold | settles once and stays — no flapping |

A struggling device is simply treated as a **lesser tier**, which means one line
turns off shadows, glow and MSAA, pulls in the draw distances and thickens the
fog — through exactly the paths that already existed for a budget phone. Distant
villagers and beasts are simulated two or three times less often, and each town's
crowd mind thinks less often too.

**And your creature stops and looks up at you.** Its own miracles are by a long
way the most expensive thing in the game — an orb, its particles, its weather,
and everything the weather then touches — so they are the first thing to go, and
it drops whatever it was reaching for. Doing it *visibly* rather than silently is
the point: a creature that halts and turns to face you is not a glitch, it is the
most legible thing on screen, and the player reads "it noticed something". It
did. It goes back to what it was doing the moment the frames recover.

## Saving looks after itself, and you can raise more than one

**There is nothing to remember.** The world writes itself down every couple of
minutes, whenever the app is put in the background (the way a phone game
actually ends), and on quit — the close is intercepted so the last two minutes
survive it. Next launch it puts you straight back where you were: no menu, no
loading step.

The land is **never written down**. Every hill, shore, forest and town site
grows back exactly from the world's **seed**, so a save holds only what *play*
has changed: your standing with the heavens and the clock, each village's
name, faith, diet, stocks, hard-won doctrine and full roster of people, and —
the part no seed could ever reproduce — your creature's whole **mind, heart,
beliefs and body**.

Loading works by handing the next scene a parcel and rebuilding around it,
so there is never a half-torn-down world. At startup there is no scene to
reload, so the parcel is simply armed from disk before anything is built.
Because the world **streams**, a town forty chunks away does not exist at load
time; its saved life waits in memory and is handed back **the moment that
village is born**, whenever you wander into it. A town you never revisit keeps
its memory — and is written out again on the next save, unchanged.

### The creatures you have raised (F5)

A creature is a long relationship, and you may reasonably want more than one: a
beast raised kindly over weeks, and a monster to let off the leash on a wet
afternoon. Neither should cost the other. So a save is not a file, it is a
**creature** — its own world seed, its own towns, its own mind — and F5 lists
them by what they have *become* rather than by slot number:

> **Baldur** ← you are here — tender wrecker · 18% grown · 1h 40m played
> **Grendel** — man-eater · 4% grown · 12m played

Switching costs neither of them anything. **Forgetting** one is the only
irreversible thing here, and it asks twice.

The very first time you ever play, the world is covered and the only thing on
screen is a field asking **what you will call it**. Naming the thing you are
about to raise is the right first act of a god, and a poor thing to bury in a
menu. A save made before profiles existed is adopted as your first creature,
comes through unnamed, and can be named from this menu without starting again.

### The workshop (F3)

Nothing here is load-bearing any more. What is left:

- **Save now** — a deliberate checkpoint, on top of the automatic ones.
- **Reload last save** — throw away what has happened since.
- **New land, same creature** — a fresh seed, a stranger's world, but your
  creature walks into it carrying every habit, belief, appetite, pound of fat
  and lesson it ever earned. The perfect way to see what a mind you have
  actually raised. Asks twice, and the arming lapses after a few seconds.
- Test cheats: prayer, a shove up the stature arc, instant conversion, and a
  printout of everything the creature currently believes, feels and expects.

## Miracles cost the creature

A miracle worked by a beast comes out of the beast. The prayer a miracle costs
*you* is a fair measure of how grand it is, so the creature is charged in the
same coin from its own reserves.

**The pool grows with the creature.** `energy` stays a 0–100 bar that everything
reads the same way; what grows is the pool that bar stands for — a hatchling's
whole reserve is 100 units, a full-grown one's is 380. So the same working
empties a small creature and barely dents a large one, and not one existing
tuning number had to change.

| Miracle | Hatchling | Half grown | Full grown |
|---|---|---|---|
| Heal | 9% of its bar | 4% | 3% |
| Rain | 15% | 7% | 4% |
| Lightning storm | 53% | 25% | 16% |
| Tornado | **65%** | 31% | 19% |

**Familiarity makes it cheaper** — a miracle watched a hundred times comes
easily, one barely understood is a wrench. Mastery takes about a third off.

**It does not know its own limit, and must not.** Nothing checks the number
before offering the deed and nothing warns it — that would hand the creature a
readout it has no business having. It tries, and if the reserves are not there
the working **fizzles**: the effort is spent, nothing happens, and the failure
is real. Since `tired` is already one of the thirteen circumstances its beliefs
are learned against, what it takes away is not *"I have 12 energy"* but
*"working miracles when weary comes to nothing"* — an idea of its own limits,
arrived at the way it arrives at everything else.

The split is deliberate: **physiology may be innate, consequences are learned.**
A tired body flinches from effort, so `cast` carries a real effort trait. But
what happens when it overreaches is discovered by overreaching.

### How big is the creature's mind?

Worth knowing before making it more complicated, and measured rather than
guessed — every learned structure written out and weighed:

| What | At the ceiling | Roughly, in RAM |
|---|---|---|
| Action values (`q`, `seen`) | 26 verbs × 20 kinds = 520 each | ~120 KB |
| Contextual weights | 520 actions × 16 circumstances | ~1.0 MB |
| Consequence rules | 520 × ~10 outcomes | ~620 KB |
| Rituals (orders that paid off) | a few thousand pairs | ~360 KB |
| Episodic memory | 400 moments × 21 fields | ~1.0 MB |
| Places, lore, people, heart | 120 + 192 + 200 + 208 entries | ~150 KB |
| **The whole mind** | | **~3.3 MB** |
| The world's remembered terrain (shared) | up to 60,000 route cells | ~14 MB |

A lived-in creature is nearer **1 MB**; 3.3 MB is every verb tried on every kind
of thing with every rule formed. Per-decision cost is bounded by what is
*nearby*, not by how much has been learned, so a creature that has lived for
hours thinks no more slowly than a newborn.

**On the 800 MB question.** We are using about two per cent of that, and adding
zeroes would not make it cleverer. Black & White's hundreds of megabytes were
overwhelmingly *art and audio*; the learned state of its creature was small too.
What buys intelligence here is **richer representations** — a compass instead of
a wire, thirteen feelings instead of one, a world model, a memory of ground, a
ledger of people — and that is where the work has gone. The budget is there when
we want it: an obvious next spend is memory of **individual objects** (this tree,
this house) rather than kinds, and a learned forward model so it can picture what
a deed would do before doing it. Neither is blocked by bytes.

## The opening lessons

A short course runs the first time you play, and only the first time: drag the
land, lift a thing, **summon a casting**, draw a rune, combine two of them, find
your creature, teach it. Then it gets out of the way for good.

Two rules keep it from being a nuisance:

- **Every step is completed by DOING it**, never by pressing OK. Each one
  watches the game for the thing actually happening, so you cannot click past a
  lesson without having learned it — and a step that is already satisfied when
  it comes up simply ticks itself.
- **It never blocks.** Nothing is disabled, nothing is modal, the world runs on
  underneath. Wander off mid-lesson and it waits.

The hint is held back until you have been stuck about nine seconds, so a player
who needs no help is never talked down to. `F4` sets the lessons aside; the
workshop replays them without touching your save.

The steps are **data** — a prompt, a hint, and a condition — which is the seed
of the scripted island to come: a mission is one of these with a place attached.

The reason this exists at all is worth recording. The author of the game forgot
how to open the casting session during his own phone playtest and asked for the
mode toggle back. If the person who wrote it cannot find the gesture, nobody
picking up a phone cold ever will.

## Demographics — why villages live or die

A villager's whole life is about **3.6 real hours**, so a run left going
overnight turns over **two complete generations**. That makes the birth rate the
single most load-bearing number in the game: a flock that cannot quite replace
its dead does not limp, it vanishes, quietly, while nobody is watching.

Two rules keep it stable, both found by simulating the population rather than
guessing at it:

- **Conception happens when a couple actually MEET.** It is not a per-second
  lottery running whether or not anyone is there. What paces a village's growth
  is how often its people go *courting* — which is what divine attention speeds
  up — rather than a coin that almost never lands.
- **A mother is free again once her child is weaned at six**, not when it
  reaches adulthood at sixteen. Sixteen years is more than half a fertile life.

Villages also read their own trend aloud. The roster shows **growing**,
**steady** or **DWINDLING** (in red), because a town dying of demographics has
no other symptom until the last funeral.

## The quiet life, and how you shape it

Most of what a creature does is neither kind nor cruel, and a creature offered
only saintly and monstrous options will pick one and become it. So the ballot
is mostly ordinary: it can **lounge** in the grass watching the world go by,
**run** for the joy of running (with a tree on its back, which is how muscle is
actually earned), **dance**, **lead the village's prayers**, or simply **stand
among the people and be looked at** — which wins belief without a drop of blood,
and is a complete non-violent road to unlocking miracles.

It cannot dance or pray until it has **watched someone** dance or pray. A
village that celebrates and worships raises a creature with a wider life than a
grim one does.

**Drives pull on traits, never on verbs.** The body knows only broad needs —
hunger, tiredness, boredom, loneliness, fear — and boredom asks for
*stimulation* without any opinion on whether that turns out to be dancing,
sprinting, showing off or flattening a house; those score identically until
experience separates them. Adding a verb means describing what it is *like*,
not writing a rule about when to do it. The single most important consequence:
nothing in the design gives violence a head start, and a creature with an
appetite for people learned it from a tie.

### Ritual

The belief engine remembers **order**, not just deeds. Every time one act
follows another and things go well, that *pairing* firms up a little — so a
creature that has found fishing-then-miracles rewarding will start fishing
first, and reach for a miracle after fishing rather than cold.

Nothing decides which sequences are meaningful. The creature simply notices
that when it does these two things in this order the day tends to go well, and
it is very often wrong about why — which is exactly what a ritual is. A habit
of order reaches the point of steering a choice after two or three repeats and
firms up to about +0.9 by a dozen; that is enough to tilt a decision and never
enough to railroad one. Rituals also fade if life stops confirming them, so a
creature can outgrow one.

This is also what keeps a life from flattening into whichever single deed
scores highest. The order matters, so the days take on a shape the creature
invented for itself — and it is a shape you can read in the workshop panel:
*"likes to fish before it casts bird_flock"*.

### Trust, and being watched

**Trust** is kept apart from bond on purpose — bond is attachment, trust is
whether your judgement is worth anything. A creature can be desperately
attached to a god it has learned to flinch from.

Praise, gifts and healing earn trust. Hurting it with your own miracles spends
it fast. So does **scolding it for something that was not cruel** — it knows
the difference between a correction and a god being unfair, and an unjust
telling-off costs you roughly fourteen times what a deserved one does.

Trust is the valve on your whole influence:

- **It copies you.** Every act of your hand near it is a lesson — what you lift,
  what you set down gently, what you hurl, who you mend — landing on the very
  same learned values it uses to choose its own deeds. There is deliberately no
  list of deeds worth copying; whatever you do is what you are teaching.
- **Below ~35 trust it stops copying you** and takes its cues elsewhere.
- **Below ~20 it keeps its distance**, sulking and shunning your hand.
- **A creature that has grown kinder than you may leave.** Low trust plus a
  temperament better than your own puts *walking away* on the ballot: it turns
  its back and goes to live by its own lights somewhere you are not.

**Exile is a condition, not an ending.** It lives out there, keeps its
distance, and will not come when called — the one command it refuses. It is
always recoverable, but it cannot be bought: coming home needs **both** trust
regained **and** a long stretch with no repeat of the thing it left over. It
remembers what you did, and every fresh offence puts the reckoning back to the
beginning. A god who pets the creature between beatings never gets it back.

## Code map

```
scenes/main.tscn              Entry point (one node; world is built in code)
scripts/main.gd               Orchestrator: sky, day/night clock, wiring
scripts/game_state.gd         Autoload: prayer, alignment, game time
scripts/save_game.gd          Autoload: profiles, autosave, and the F3 levers
scripts/audio/sound_bank.gd   Autoload: all sounds, synthesized in code
scripts/util.gd               Primitive-shape building helpers
scripts/nav_field.gd          Autoload: obstacle field for local steering, plus
                              a bounded A* router costed from the terrain
scripts/player/
  camera_rig.gd               God-game camera (pan/rotate/zoom)
  divine_hand.gd              THE hand: hover, grab, throw, drag, gestures
  gesture_recognizer.gd       Mouse-trail → gesture classification
  gesture_trail.gd            Glowing trail drawn while gesturing
scripts/world/
  world_gen.gd                Endless world: chunks, noise, biomes, villages
  chunk.gd                    One 48m tile: mesh, collision, water, scatter
  village.gd                  Belief/conversion, diet, housing, pen, jobs
  village_hive.gd             The crowd mind: what the town feels and does, once
  house.gd                    Dwellings: sizes, health, age, collapse
  edubba.gd                   The schoolhouse: gathers children, frees mothers
  wild_tree.gd                Harvestable trees (biome-styled)
  rock_deposit.gd             Harvestable stone
  farm.gd                     Crop growth, tending, rain bonus, harvest
  food_store.gd               Storehouse: plants, meat, lumber, stone
  food_item.gd                Physical food: grain sheaves & species-named meat
  corpse.gd                   The dead, as physical objects
  terrain_scars.gd            Land that remembers: craters, cones, ripples —
                              the one part of the ground the seed cannot rebuild
  nightfall.gd                The night's small, fixed pool of real lights,
                              handed to whichever hearths you are nearest
scripts/animals/animal.gd     EVERY beast, one data table: livestock, pets,
                              predators, prey — taming, riding, guarding
scripts/villager/villager.gd  Full villager lives: needs, age, pregnancy,
                              morality, demand-driven jobs (state machine)
scripts/creature/
  creature.gd                 The creature itself: feelings, states, deeds,
                              pet/scold training — it coordinates the modules
  creature_mind.gd            The learning brain: action values, curiosity,
                              conscience, satiation, emergent character
  creature_ethos.gd           The six-axis moral compass and what it names
  creature_heart.gd           Thirteen feelings at once; learning its own heart,
                              and reading other people through it
  creature_beliefs.gd         Episodes, credit assignment, contextual weights,
                              lore, places, recall — what it believes, and WHEN
  creature_bonds.gd           Who it knows, by name
  creature_foresight.gd       What it thinks a deed would DO — one move ahead
  creature_record.gd          Writing a creature down, and giving it back
  creature_steering.gd        Routes, waypoints, wedges, and bad ground
  creature_blessings.gd       Flight and footing on water: what a god has laid
                              on it, and how long each lasts
  creature_body.gd            Stomach, digestion, fat, muscle and energy
  creature_eyes.gd            Perception only: nearest X, circumstances, plights
  creature_look.gd            Alignment colour, expressions, blend shapes, and
                              the godly radiance it gives off after dark
scripts/miracles/
  spellbook.gd                The GRAMMAR: runes, recipes, and the blend fallback
  miracle_manager.gd          Catalog, effects, unlock ladder, power scaling
  miracle_orb.gd              Generic conjured-and-thrown miracle carrier
  fireball.gd                 The throwable fire miracle: ballistic, explosive
  storm_cloud.gd              Swirling, breathing, fading layers of vapour
scripts/ui/hud.gd             Bars, legend, tooltips, help
scripts/ui/debug_menu.gd      The F3 workshop: save/load/regenerate + cheats
scripts/ui/cast_overlay.gd    The casting ring and countdown — what the mode looks like
scripts/ui/rune_readout.gd    What you are drawing, drawn: the live glyph and
                              the runes already on the slate, glowing
scripts/ui/tutorial.gd        The opening lessons: data-driven, completed by doing
scripts/ui/profile_menu.gd    The creatures you have raised: switch, name, begin
scripts/ui/touch_controls.gd  Touchscreen-only buttons: Cast/Move mode,
                              follow-the-creature camera lock
```

### Architecture principles (read before adding systems)

1. **Systems first.** Every mechanic is a plain-code system with a narrow
   interface. No logic buried in editor-only scene configuration.
2. **Extend at the seams.** New miracles go in `MiracleManager.MIRACLES` +
   one `_cast_*` method. New villager behaviors go in the `Villager.State`
   machine + `_decide()`. New needs are one variable + one decay line + one
   action that satisfies them.
3. **Groups over hard references.** Systems find each other via node groups
   (`villagers`, `creature`, `food`, `farms`, `pickable`, `village`) so
   features stay decoupled.
4. **Everything tunable lives in `const`s at the top of its file.**

## Packing a demo build

Export presets for **Linux**, **Windows**, and **Web** are committed in
`export_presets.cfg`, and everything lands in `builds/` (git-ignored).

**One-time setup** (per machine): open the project in the editor, then
*Editor → Manage Export Templates → Download and Install*. Templates must
match the editor version exactly (4.7-stable).

Then either export from the editor (*Project → Export… → Export Project*),
or pack everything from the terminal:

```sh
./build.sh              # Linux + Windows + Web, zipped in builds/
./build.sh Web          # just one platform
GODOT=~/Apps/godot ./build.sh   # if godot isn't on your PATH
```

Notes:
- Desktop builds are **single-file** (the game data is embedded in the
  executable) — send the zip, they unzip and run. No installer.
- The Web build is exported **without threads**, so it runs from any
  static host — itch.io (upload `hand-of-heavens-demo-web.zip`, mark
  "played in browser"), GitHub Pages, or locally with
  `python -m http.server -d builds/web`. No special headers needed.
- The whole game is generated from code — no assets — so a demo zip is
  only as big as the engine runtime (~40 MB desktop, ~30 MB web).
- Cross-exporting Windows builds from Linux works out of the box; icons
  and code signing are left unset (fine for a demo).

### Android (.apk)

An **Android** preset is committed too (arm64, debug-signed — installable
on any phone, not store-ready). One-time setup on your machine:

1. **JDK 17** — e.g. `sudo apt install openjdk-17-jdk` (or your distro's
   equivalent; on an immutable distro, a toolbox/distrobox works fine).
   Find the path Godot wants with
   `java -XshowSettings:properties -version 2>&1 | grep java.home`.
   ⚠️ **Distrobox users**: a JDK installed in the box lives at
   `/usr/lib/jvm/...` *inside the container* — Godot can only use it if
   Godot also runs inside that box. If you run Godot on the host, use a
   tarball JDK in your home directory instead (both sides see `$HOME`):
   extract [Temurin 17](https://adoptium.net/temurin/releases/?version=17)
   to `~/Apps/jdk-17` and point Godot there. (`~/Android/Sdk` is in
   `$HOME` already, so the Android SDK has no such problem.)
2. **Android SDK** — easiest is [Android Studio](https://developer.android.com/studio)
   (installs the SDK to `~/Android/Sdk`); or the standalone
   `cmdline-tools` + `sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34"`,
   then `sdkmanager --licenses` to accept licenses.
3. **Debug keystore** — Android Studio creates `~/.android/debug.keystore`
   on first launch. Without Android Studio, make one yourself:
   ```sh
   keytool -keyalg RSA -genkeypair -alias androiddebugkey \
     -keypass android -keystore ~/.android/debug.keystore -storepass android \
     -dname "CN=Android Debug,O=Android,C=US" -validity 9999
   ```
4. **Point Godot at all three** — *Editor → Editor Settings → Export →
   Android*: set *Java SDK Path* (the JDK 17 folder), *Android SDK Path*
   (e.g. `~/Android/Sdk`), and *Debug Keystore*
   (`~/.android/debug.keystore`, user `androiddebugkey`, password `android`).
5. Export templates installed (same dialog as the desktop platforms).

Then:

```sh
./build.sh Android          # -> builds/hand-of-heavens-demo.apk
adb install builds/hand-of-heavens-demo.apk   # or copy to the phone and tap it
```

(Installing by tapping the file requires allowing "install unknown apps"
for your file manager — normal for any demo APK.)

**Touch controls** (appear automatically on touchscreens):

| Touch | Action |
|---|---|
| One finger | Everything the left mouse does — governed by the Mode button |
| **Mode** button | Toggle **Move** (drag land / pick / place / throw) ↔ **Cast** (one-finger gesture drawing) |
| **Creature** button | Camera locks to and follows your creature (pan to release) |
| Pinch | Zoom |
| Two-finger drag | Orbit the camera freely (yaw + tilt) |

The UI scales to the device (900-line logical height, width expands to
the phone's aspect). Not yet touchable: creature pet/scold and diet
policy — they still need P/L and 1–4 on a keyboard.

## Headless smoke test

CI-friendly check that the whole world boots, gestures classify, and all four
miracles cast without script errors:

```sh
godot --headless --path . -- --smoke-test
```

## Roadmap (after the PoC)

- ~~Villager lifecycle: age, death, children~~ ✔
- ~~Diet policies incl. cannibalism~~ ✔
- ~~Good/evil karma for player, creature, and villagers~~ ✔
- ~~Endless chunked terrain, biomes, elevation, water~~ ✔
- ~~Neutral villages + conversion~~ ✔
- ~~Jobs: builder/lumberjack/quarrier; housing with decay; homelessness~~ ✔
- ~~Day/night cycle (16 years per day)~~ ✔
- ~~Livestock, taming, riding, guard dogs, predators~~ ✔
- ~~Procedural sound~~ ✔
- ~~Creature learning (reward/punish via petting/scolding)~~ ✔ — next: direct control, leashes
- ~~A moral compass with more than two directions~~ ✔
- ~~An emotion engine, and empathy paid for in experience~~ ✔
- ~~A crowd mind so villages respond as towns, not as crowds of individuals~~ ✔
- ~~Real pathfinding, and a creature that learns bad ground~~ ✔
- **Terrain-deforming miracles** — the world as something it can really mess
  about with rather than only learn: flooding a valley to open a river,
  cracking the earth into an actively erupting volcano (an end-game working),
  fireballs that scar and gouge, force bolts that leave steaming craters
- Festivals, music, dance, named relationships (lovers, parents, friends)
- **The opponent**: a rival god with its own villages, creature, and
  temperament (all systems are per-instance already to make this possible)
- Miracle progression: unlocks, upgrades, mutually exclusive paths
- Full controller support
- Real art and animation (someday; the sound is already ours)

## Team workflow

- `main` is always runnable. Work on feature branches
  (`feature/creature-learning`), merge via pull request.
- Scene files (`.tscn`) are text — but they merge badly. Avoid two people
  editing the same scene in the same sprint. (Building worlds in code, as we
  do now, largely sidesteps this.)
- Never commit the `.godot/` folder (already gitignored).
