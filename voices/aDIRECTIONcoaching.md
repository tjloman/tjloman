# Direction — coaching notes for every cue in the game

Director's scratch. One row a cue, and a section under it with the direction.
Nothing here is binding; it is what somebody should be told before they open
their mouth or their sampler.

## How to find things

Every cue has a search tag in square brackets: **`[baa]`**, **`[howl]`**,
**`[greet_morning]`**. The tag is the filename without its extension, and it is
the exact string the game asks for, so Ctrl-F for a cue name lands on its entry
and nowhere else. The tags appear once in the index and once at their section,
so `Find Next` walks you straight from the table to the direction.

Drop `<tag>.ogg` (or `.wav`, `.mp3`) in this folder and it replaces whatever the
game was doing before — a synthesized waveform for most of these, silence for
the spoken ones. Delete it and the old behaviour comes back. **Record three
takes** where you can: `howl_1.ogg`, `howl_2.ogg`, `howl_3.ogg` are chosen
between at random, and the game pitch-jitters on top. A single take heard twice
in a minute is worse than no take at all.

Everything is positional 3D audio. Record dry and quiet; the game sets distance
attenuation and level at each call site, and a cue mastered loud will clip
against the twenty-four other things a village is doing.

---

## The index

| Cue | Brief | Direction in one line |
|---|---|---|
| **`[baa]`** | a sheep | bored, not distressed; the sound of an animal with nothing to do |
| **`[cluck]`** | a chicken | short, busy, self-important; three or four in a row is one cue |
| **`[oink]`** | a pig | wet, low, contented — also used for dung, quietly, which is a joke |
| **`[neigh]`** | a horse | one animal, heard across a field; never a whinny of panic |
| **`[bark]`** | a dog | a working dog telling you something, not a pet wanting attention |
| **`[howl]`** | a wolf, far off | the one that makes a player look up from what they were doing |
| **`[roar]`** | the creature | pitched by its size at the call site — record it big and let the game shrink it |
| **`[scream]`** | a person past bearing it | alight, struck, or thrown — see the section; the hardest cue in the game and the one to record last |
| **`[croak]`** | a frog | comic, wet, unhurried; the only voice in a wetland at night |
| **`[saw]`** | felling timber | the pull stroke, not the push; wood giving way, not metal |
| **`[pick]`** | quarrying stone | one strike and its ring; a small chip, not a demolition |
| **`[hammer]`** | building, and a weapon landing | a single blow with something behind it, on wood |
| **`[murmur]`** | a person half-talking to themselves | the sound of thinking out loud, no words |
| **`[coo]`** | small birds, and a portal | gentle, round, reassuring; the sound of nothing being wrong |
| **`[caw]`** | crows | harsh and flat; carrion weather |
| **`[screech]`** | a bird of prey, and a mauling | the one genuinely unpleasant sound in the game |
| **`[boom]`** | a fireball, a volcano | felt more than heard; low, with the air moving |
| **`[chatter]`** | a crowd, a squirrel | many voices at a distance, none of them distinguishable |
| **`[drum]`** | the hand striking the earth | a flat palm on a taut skin — the player's own heartbeat |
| **`[whisper]`** | kindling catching, the hand near something | the intake before a fire, or before a decision |
| **`[crickets]`** | night, open grass | LOOP. seamless, no single cricket identifiable |
| **`[bees]`** | day, over flowers | LOOP. warm, close, slightly maddening |
| **`[flies]`** | day, over carrion | LOOP. the same idea as bees and entirely unwelcome |
| **`[peepers]`** | night, near water | LOOP. small frogs, a wall of them, pulsing |
| **`[chitter]`** | day, in trees | LOOP. squirrels and small birds arguing |
| **`[rustle]`** | night, in trees | LOOP. leaves and something moving in them |
| **`[greet_morning]`** | a villager, waiting to decide, before ~11am | half to themselves, unhurried; see below |
| **`[greet_afternoon]`** | …between ~11am and ~5pm | the same person, warmer, a little tired |
| **`[greet_evening]`** | …between ~5pm and dark | winding down; the day is behind them |
| **`[greet_night]`** | …after dark | quiet, because others are asleep |
| **`[yawn]`** | the fallback when the hour has no greeting | a real yawn, not a performed one |

---

## The direction

### The animals

**`[baa]`** · **`[cluck]`** · **`[oink]`** · **`[neigh]`** · **`[bark]`** ·
**`[croak]`**

These fire on a per-species chance every few seconds from `Animal.SPECIES`, so a
field of twenty sheep is twenty independent rolls. **The failure mode is
rhythm.** Anything with a recognisable attack lands on a beat when it repeats,
and a meadow starts to sound like a drum machine. Record these ragged — vary the
length, start slightly off, let one trail. The game jitters pitch ±12% but it
cannot fix timing.

None of them are in distress. A distressed animal is a specific event the game
handles elsewhere; these are the sound of livestock existing.

**`[howl]`** is the exception and the most important animal cue in the game. It
fires when a wolf pack is generated in the world, once, at the pack's position,
and it is frequently the only warning a player gets. It must carry a long way
and it must interrupt. One animal, alone, far off — not a pack chorus, which
reads as ambience. The thing to aim at: a player mid-way through building a barn
should stop and look at the treeline.

**`[roar]`** is the creature and it is pitched at the call site by how big the
creature has grown — a fifteen-fold range off one waveform. **Record it at the
top of that range**, slow and enormous, and let the game pitch it up for a young
one. A roar recorded small and pitched down becomes a growl and loses the throat.

### The work

**`[saw]`** · **`[pick]`** · **`[hammer]`**

Villager work loops these on a per-job interval, so they are heard hundreds of
times an hour. They have to survive that, which means **no personality at all**
— any distinguishing feature becomes a tic within ten minutes. Short, dry,
mid-range, no tail. Think of them as the punctuation of a working village rather
than as sounds in their own right.

`[hammer]` doubles as a melee weapon connecting (`Weapon.strike`), so it wants
enough weight to read as a blow without being a demolition.

### The one that is nobody's favourite day at work

**`[scream]`**

This plays when a person is **on fire**, has been **struck**, or is **turning
over in the air** because a god threw them. There is nothing sensible left for
them to do in any of the three, which is the whole reason the cue exists: fear
has a behaviour and this does not.

**Direction.** It is a cry for *help*, not a horror-film scream. The difference
is that a cry for help is addressed to somebody — there is a hope in it, and
the hope is what makes it land. Start it already at full voice; there is no
wind-up when you are alight. Let the throat tighten across it rather than the
pitch rise: the rasp coming in is what says this has been going on longer than
the half-second you can hear.

**Keep it short.** Under a second. A scream that outlasts the fall is a comedy,
and the game will cut you off at the landing either way.

**Do not perform the death.** The game decides whether they live — a healing
shower, a hand, a pond to land in — and a take that has already given up
contradicts the rescue the player is at that moment attempting. Three takes,
and let one of them be somebody who thinks they are going to be caught.

**The same waveform serves animals**, pitched down between 0.55 and 0.78 and
roughened, so there is no separate beast cue to record. If that reads badly
once it is in, a `[scream_beast]` is a two-line change at the call site.

**Level.** Quiet. This is already the loudest thing in the mix by context, and
the game rations it hard: one cry anywhere in the world every 0.22s, and no
single body more than once every 2.6s. A take mastered hot turns a burning
street into distortion.

### The voices of a crowd

**`[murmur]`** · **`[chatter]`** · **`[whisper]`**

`[murmur]` is a single person thinking out loud with no words in it, and it is
the fallback for the spoken lines below — so it is the sound a village makes
until somebody records the real thing. It is also what a villager makes at
worship. It should be possible to hear it as reverent or as idle depending on
what is around it, which means **no clear emotion in the take**.

`[chatter]` is many people at a distance and no one of them audible. The test:
if a listener can pick out a single voice, it is wrong.

`[whisper]` is the intake of breath before something happens — fire catching,
the hand closing on something. Not a voice whispering words. Air.

### The birds

**`[coo]`** · **`[caw]`** · **`[screech]`**

Chosen between by the bird-flock miracle according to the player's alignment:
`[coo]` for a saintly hand, `[caw]` in the middle, `[screech]` for a monstrous
one. **They are one cue in three moods** and should be recorded as a set, by the
same throat if possible, so a player who turns cruel hears their own birds go
wrong rather than hearing a different animal.

`[screech]` also fires when a villager is being mauled. It is the one genuinely
unpleasant sound in the game and should stay that way.

### The big ones

**`[boom]`** is a fireball landing and a volcano opening. It plays at the call
site's own volume, which varies a great deal — a gout is quiet and a full
firestorm is not — so **record the loud version** and let the game bring it
down. Low, with air movement in it; felt before it is identified.

**`[drum]`** is the player's own hand striking the earth, and its volume is set
by how hard they struck. It is the most frequently heard cue in the game that
the player CAUSED, which makes it the closest thing this game has to a UI sound.
A flat palm on a taut skin. No reverb — it happens where the player is looking.

### The loops

**`[crickets]`** · **`[bees]`** · **`[flies]`** · **`[peepers]`** ·
**`[chitter]`** · **`[rustle]`**

These are held open by TreeFriends and ridden by volume as the player moves, so
they run for minutes at a time. **The loop point is the whole job.** The game
splices 0.25s of the tail back over the head to hide the join in its synthesized
versions; a recording has to solve that itself. Anything with a discernible
event in it — one loud cricket, one bee passing close — becomes a tick you
cannot stop hearing after the third pass.

Record long. Sixty seconds is not too much.

`[bees]` and `[flies]` are deliberately the same idea in two moods: one over a
meadow and one over a corpse. If a player can tell which they are hearing
without looking, that is exactly right.

### The spoken lines

**`[greet_morning]`** · **`[greet_afternoon]`** · **`[greet_evening]`** ·
**`[greet_night]`** · **`[yawn]`**

These exist for a specific mechanical reason and the direction follows from it.

A villager whose plan has run out waits its turn in the spool before choosing
what to do next. Usually that is a fifth of a second. But when a whole town
re-decides at once — a wolf, a job filling, a miracle — the wait becomes long
enough to see, and a body standing perfectly still reads as broken.

**So these recordings exist to make a pause look like a person thinking.**
That is the note. Not a greeting across a courtyard; the half-voiced thing
somebody says to nobody in particular while deciding whether to go to the field
or the river. Unhurried, trailing off, at the level of talking to yourself.

The archaic register ("good morning to ye") is the house voice — keep it, but
say it the way a real person says a phrase they have said ten thousand times,
which is to say quickly and without listening to themselves.

One villager in sixteen speaks, and the whole town is limited to one voice every
five seconds. **These are heard rarely and have to bear repetition when they
are.** Under two seconds each. Three takes minimum; five is better.

`[yawn]` catches any hour with no greeting recorded, so a folder containing only
`yawn.ogg` already works. A real yawn — the kind that happens to you — rather
than a performed one.

---

## Scratch

Notes, arguments with yourself, things to try. Nothing below here is read by
anything.

- Sex and age: villagers have both (`is_female`, `age`) and the game does not
  yet pick a voice by either. When there are enough takes to want it, the
  filename convention to reach for is probably `greet_morning_f_1.ogg` — say so
  here before recording a hundred files against the wrong scheme.
- The archaic register is currently only in the greetings. Worth deciding
  whether the whole game speaks that way or only the villagers.
- `[roar]` is the only cue with a real emotional range to play and it has one
  take. Anger, hunger, delight and fear are four different animals.
