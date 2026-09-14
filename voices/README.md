# Voices

Drop a sound file here and the game starts using it. Delete it and the
synthesized version comes back. This works for **any** cue the game plays, not
only the spoken ones — `howl.ogg` replaces the synthesized wolf everywhere it
fires. Nothing here is required — the game ships and runs
with this folder empty, and there is not one audio file anywhere else in the
project (see `scripts/audio/sound_bank.gd`: every other sound is oscillators).

Extensions checked, in order: `.ogg` `.wav` `.mp3`

## Takes, not a take

`yawn.ogg` works. So does `yawn_1.ogg`, `yawn_2.ogg` … up to `yawn_8.ogg`, and
when there is more than one a take is chosen at random each time. **Record
several.** A town says these constantly, and one recording heard twice in a
minute is worse than no recording at all. Pitch is already jittered ±6% on top,
so three takes go a long way.

## Direction

**[`aDIRECTIONcoaching.md`](aDIRECTIONcoaching.md)** is the coaching document:
every cue in the game by name, what it is, and how it should be performed —
searchable by tag, so Ctrl-F for `[howl]` lands on the direction for it. Read
that before recording anything. It covers the synthesized cues too, because a
recording dropped in here replaces any of them, not only the spoken lines.

## Lines the game asks for

| File | Said when |
|---|---|
| `greet_morning` | a villager is waiting on a decision, before about 11am |
| `greet_afternoon` | …between about 11am and 5pm |
| `greet_evening` | …between about 5pm and nightfall |
| `greet_night` | …after dark |
| `yawn` | the fallback when there is no greeting for the hour |

The greeting is tried first, then `yawn`, then a synthesized murmur — so a
folder with only `yawn.ogg` in it already works, and one with only
`greet_morning.ogg` works in the mornings.

### What they are for

A villager whose plan has run out waits its turn in the spool before choosing
what to do next (see `scripts/spool.gd`). Usually that is a fifth of a second
and nothing is done about it. But when a whole town re-decides at once — a wolf
comes over the hill, a job fills, a miracle lands — the wait becomes long enough
to see, and a body standing perfectly still reads as broken.

So they stretch, and one of them says something. **These recordings exist to
make a pause look like a person thinking**, which is what it is. Write them
accordingly: unhurried, half to themselves, the sort of thing somebody says
while deciding whether to go to the field or the river. Not a hail across a
courtyard.

Roughly one wait in sixteen produces a voice, and the whole town is limited to
one voice every five seconds, so these are heard rarely and should bear it.

### Length and level

Keep them under about two seconds. They are positional — 3D, audible to about
40m — and they play over whatever else the village is doing, so record them
quiet rather than loud; the game attenuates them a further 3dB.

## Animation

The stretch is a clip on the villager's rig, not a file here. Call it `stretch`
(or `yawn`, `think`, `ponder` — all accepted) and it plays automatically for
the same pause. See `models/README.md`; until a rig has one, the pause is
carried by the voice alone.
