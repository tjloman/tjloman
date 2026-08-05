# Cart telemetry — the contract

The cart is a second drivetrain: two motors, its own pack, a solar panel, and
regenerative braking. Energy flows *into* it as well as out, which no
off-the-shelf ebike protocol covers.

So this is the interface the app expects the cart to speak. It is defined
before the cart exists on purpose — it is far cheaper to build firmware
against a fixed contract than to reverse-engineer one later, and it means the
app works the day the cart first powers up.

If the cart ends up speaking something else, that is fine too: write a new
profile in `scripts/ble/profiles/` and nothing else changes. This document is
the recommendation, not a constraint on the metal.

## Why BLE GATT with small frames

Whatever microcontroller ends up in the cart (an ESP32 or an nRF52 is the
obvious choice — both do BLE peripheral in a few hundred lines), it will be
sampling a shunt monitor and two motor controllers and wants to publish that
cheaply.

**Every frame here fits in 20 bytes.** That is the payload of a single BLE
notification at the default 23-byte ATT MTU. Staying under it means the
firmware never has to negotiate a larger MTU, never has to fragment, and never
has a partial frame to reassemble — and MTU negotiation is one of the most
common places a BLE link quietly stops working after a phone update. Three
small characteristics beat one big one.

All fields are **little-endian**, which is what an ESP32 or nRF52 writes
natively — a `memcpy` of a packed struct is a valid frame.

## Service

```
service   0000c001-6361-7274-8000-00805f9b34fb      ("cart" in the middle)
  c002    PACK      notify, 18 bytes    battery
  c003    MOTORS    notify, 16 bytes    the two drive motors
  c004    SOLAR     notify, 14 bytes    panel and charge controller
  c005    COMMAND   write,   2 bytes    lights, regen level, assist
  c006    INFO      read,   20 bytes    fixed facts, read once on connect
```

Notify each of the three on change, or at 1 Hz while moving and 0.1 Hz at
rest — the app samples what it needs and does not mind repeats.

### c002 PACK

| Offset | Type | Meaning |
|---|---|---|
| 0 | u8 | frame version, currently `1` |
| 1 | u8 | status bits: 0 charging · 1 discharging · 2 balancing · 3 fault · 4 solar feeding · 5 regen feeding |
| 2 | u16 | pack voltage, 0.01 V |
| 4 | i16 | pack current, 0.01 A — **positive is into the pack** |
| 6 | u8 | state of charge, % |
| 7 | u16 | energy remaining, Wh |
| 9 | u16 | pack capacity, Wh |
| 11 | i16 | pack temperature, 0.1 °C |
| 13 | u16 | charge cycles |
| 15 | u16 | lowest cell, mV |
| 17 | u8 | cell spread, mV (capped at 255) |

Signed current is the important one. The app integrates it directly, so solar
and regen show up as energy returned rather than needing separate bookkeeping,
and the measured Wh/mile is a *net* figure — which is the number that actually
predicts how far you get.

### c003 MOTORS

| Offset | Type | Meaning |
|---|---|---|
| 0 | u8 | frame version |
| 1 | u8 | motor count (2) |
| 2 | i16 | motor 0 current, 0.01 A — **negative is regenerating** |
| 4 | i16 | motor 0 temperature, 0.1 °C |
| 6 | u16 | motor 0 rpm |
| 8 | i16 | motor 1 current, 0.01 A |
| 10 | i16 | motor 1 temperature, 0.1 °C |
| 12 | u16 | motor 1 rpm |
| 14 | u8 | regen level in effect, 0–5 |
| 15 | u8 | flags: 0 thermal derate active · 1 controller fault |

Per-motor temperature matters more on a cart than on a bike: a trailer motor
sits low, gets no airflow behind a fairing, and is the thing most likely to
derate on a long climb. Seeing one motor run hotter than the other is also the
earliest sign of a dragging brake or a mis-tracked wheel.

### c004 SOLAR

| Offset | Type | Meaning |
|---|---|---|
| 0 | u8 | frame version |
| 1 | u16 | panel voltage, 0.01 V |
| 3 | u16 | panel current, 0.01 A |
| 5 | i16 | charge power, W |
| 7 | u16 | harvested today, Wh |
| 9 | u32 | harvested lifetime, Wh |
| 13 | u8 | controller state: 0 tracking · 1 bulk · 2 absorption · 3 float · 4 off |

Harvest-today is worth having the firmware own rather than the app: the app is
not always running, and a solar day that only counts while a phone was awake
is a useless number.

### c005 COMMAND

Two bytes: opcode, then value.

| Opcode | Value | Effect |
|---|---|---|
| `0x01` | 0–3 | lights off / running / bright / flashing |
| `0x02` | 0–5 | regen strength |
| `0x03` | 0/1 | cart assist enable |
| `0x04` | 0/1 | charge the bike pack from the cart |
| `0x05` | — | send all three notify frames now |

### c006 INFO

Read once on connect. 20 bytes: version (u8), motor count (u8), pack capacity
Wh (u16), panel rating W (u16), wheel circumference mm (u16), then a 12-byte
firmware string, NUL-padded.

## Notes for whoever builds the firmware

**Publish raw, not derived.** Send volts and amps; let the app integrate.
Firmware that reports a "range" or a "percent" it computed itself is firmware
whose arithmetic you cannot fix without a reflash on the road.

**Own the counters that must survive a reboot** — harvest today, harvest
lifetime, cycles. Everything else can be stateless.

**Keep advertising even when asleep**, or use a connectable low-power mode.
The app reconnects on its own whenever the cart is in range; that only works
if the cart is discoverable without someone pressing something.

**A shunt on the pack, not on the motors,** is what makes the energy numbers
honest. Motor current is useful for diagnosis; pack current is what the range
estimate is built on. An INA226 or similar on the pack side is enough.

**Name the peripheral something recognizable** — anything containing "cart"
lands in the right role automatically the first time the app sees it.

## What the app does with it

- Two packs are tracked separately and shown separately: the Saber's own pack
  and the cart's. Range is computed from the total energy that can reach the
  wheels.
- Energy is integrated as a signed ledger, so a day shows Wh out, Wh back from
  regen, and Wh from the sun — and a long descent can genuinely end with more
  in the pack than it started.
- Every pack sample is written to the logbook against your position, so the
  trip ends up with a solar harvest map and a regen profile of every descent.
- Motor temperature and BMS protection events become logbook entries, because
  a cut-out you cannot explain three states later is worse than the cut-out.
