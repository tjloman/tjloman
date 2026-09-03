#!/usr/bin/env python3
"""THE RUNE COUNCIL BOT — suggestions and polls, in Discord, with no libraries.

    !runes                              the alphabet
    !table   fire water                 what that drawing does TODAY
    !suggest fire water | Name | idea   put forward what it should do instead
    !board   fire water                 everything put forward for it so far
    !poll    fire water                 turn those into a real Discord poll

NOTHING TO INSTALL. Every Discord bot library exists to hold a websocket open
to the gateway, and a websocket is the one thing Python's standard library has
no client for — which is the whole reason `pip install discord.py` was in the
way. So this does not use the gateway. It ASKS the channel what has been said,
every few seconds, over ordinary HTTPS, with `urllib` — the same standard
library everything else in this repository runs on.

The cost of that choice is honest and small: a command is answered within a
few seconds rather than instantly, and people type `!suggest` instead of a
slash command with autocomplete. For a room of people thinking about rune
combinations, neither matters.

NO WEBHOOK ANYWHERE. A webhook URL is a bearer credential with no revocation
short of deleting it, and it has to be pasted into whatever posts with it. The
bot's token is a credential too — but it lives in one environment variable on
one machine, resets in two clicks if it leaks, and NOBODY TAKING PART EVER
TOUCHES IT. They type a message; that is the whole interface.

IT NEEDS NO HOSTING. Run it while the group is working, Ctrl-C afterwards.
Suggestions are written to a JSON file beside this script as they arrive, in
the same shape the suggestion page exports and `discord_poll.py` reads — one
pipeline, three ways in.

Every reply carries the drawing's CURRENT reading, taken from spellbook.gd
through miracle_audit.py, so a suggestion is always made against what the
combination really does rather than what anyone remembers.

SETUP, once:

  1. discord.com/developers/applications -> New Application -> name it.
  2. Bot (left sidebar) -> Reset Token -> copy it. Discord shows it ONCE.
  3. Still on Bot: turn ON "Message Content Intent". Reading what people
     typed is the whole job, and Discord gates that behind this toggle.
     (No verification needed while the bot is in under 100 servers.)
  4. OAuth2 -> URL Generator -> scope `bot`, permissions `Send Messages` and
     `Read Message History`. Open the URL, pick your server.
  5. In Discord: Settings -> Advanced -> Developer Mode ON, then right-click
     the channel you want it in -> Copy Channel ID.

Then:

    export DISCORD_BOT_TOKEN='…'       # never paste this anywhere else
    export DISCORD_CHANNEL_ID='…'
    python3 tools/rune_bot.py

It prints who it logged in as and starts listening. Ctrl-C to stop.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import miracle_audit

BOOK = miracle_audit.Book()
STORE = os.path.join(HERE, "suggestions.json")

API = "https://discord.com/api/v10"
PREFIX = os.environ.get("RUNE_BOT_PREFIX", "!")
POLL_EVERY = 3.0     # seconds between asking the channel what is new
NAME_MAX = 55        # Discord's cap on a poll answer, so also on a name
IDEA_MAX = 400
ANSWERS_MAX = 10     # Discord's cap on poll answers
ARROW = "▸"


## Talking to Discord ---------------------------------------------------------

def call(token, method, path, body=None, retries=4):
    """One REST call. Returns parsed JSON, or None if it could not be made.

    429 is Discord's rate limit and carries `retry_after` in seconds; anything
    else is reported once and gives up, because a bot that hammers a failing
    endpoint in a loop is worse than one that misses a message.
    """
    url = API + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bot " + token,
        "Content-Type": "application/json",
        "User-Agent": "DiscordBot (hand-of-the-heavens, 1.0)",
    })
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                raw = r.read().decode("utf-8")
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:300]
            if e.code == 429 and attempt < retries - 1:
                wait = 2.0
                try:
                    wait = float(json.loads(detail).get("retry_after", wait))
                except Exception:
                    pass
                time.sleep(min(wait, 30.0))
                continue
            if e.code == 401:
                raise SystemExit(
                    "Discord rejected the token (401).\n"
                    "Reset it in the Developer Portal under Bot, and make sure\n"
                    "DISCORD_BOT_TOKEN holds the BOT token — not the "
                    "application id, and not the client secret.")
            if e.code == 403:
                print("  Discord said no (403). The bot probably lacks Send"
                      " Messages or Read Message History in that channel.",
                      file=sys.stderr)
                return None
            print("  HTTP %d on %s %s: %s" % (e.code, method, path, detail),
                  file=sys.stderr)
            return None
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < retries - 1:
                time.sleep(2.0 * (attempt + 1))
                continue
            print("  could not reach Discord: %s" % e, file=sys.stderr)
            return None
    return None


def say(token, channel, content, poll=None):
    body = {}
    if content:
        body["content"] = content[:1990]
    if poll is not None:
        body["poll"] = poll
    if not body:
        return None
    return call(token, "POST", "/channels/%s/messages" % channel, body)


## Reading a drawing ----------------------------------------------------------

def parse_runes(text):
    """'fire water', 'fire+water', 'Fire, Water' -> ['fire', 'water'].

    Raises ValueError naming the offending word — being told "that is not a
    rune" with no clue which one is a genuinely annoying thing to be told.
    """
    words = [w.strip().lower() for w in
             text.replace("+", " ").replace(",", " ").split()]
    words = [w for w in words if w]
    if not words:
        raise ValueError("Name at least one rune. `%srunes` lists them." % PREFIX)
    if len(words) > 6:
        raise ValueError("Six runes is more than anyone will draw at once.")
    for w in words:
        if w not in BOOK.base:
            raise ValueError("`%s` is not a rune. They are: %s."
                             % (w, ", ".join(BOOK.runes)))
    return words


def pretty(miracle):
    return miracle.replace("_", " ").title()


def reading_of(draw):
    """What the drawing does today: the outcome, how it got there, and what it
    costs. Straight from the game's own tables through miracle_audit."""
    r = BOOK.interpret(draw)
    cost = round(BOOK.cost(draw))
    tier = BOOK.tier_needed(draw)
    if r["how"] == "NAMED":
        what = pretty(r["miracle"])
        how = "a named miracle, written by hand"
    elif r["how"] == "AMPLIFIED":
        what = "%s at %.2f× potency" % (pretty(r["miracle"]), r["potency"])
        how = "one rune repeated — the same miracle writ larger"
    else:
        parts = ", ".join("%s ×%.2f" % (pretty(m), p) for m, p in r["parts"])
        what = "no name of its own (%s)" % parts
        how = ("a multi-cast: every rune's miracle at once, each weakened."
               " Four fifths of the spellbook lands here")
    return what, how, cost, tier, r["how"]


def drawing_line(draw):
    return " + ".join(draw)


def today_line(draw):
    what, how, cost, tier, _ = reading_of(draw)
    return ("**%s** %s %s\n_%s · %d prayer · tier %d_"
            % (drawing_line(draw), ARROW, what, how, cost, tier))


## The store ------------------------------------------------------------------
##
## One JSON file, the same shape the suggestion page exports and
## discord_poll.py reads. Rewritten whole on every change: this is tens of
## entries from a focus group, not a database, and a file you can open and read
## is worth more here than anything cleverer.

def load():
    try:
        with open(STORE, encoding="utf-8") as fh:
            return json.load(fh)
    except (FileNotFoundError, ValueError):
        return []


def save(groups):
    tmp = STORE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(groups, fh, indent=1, ensure_ascii=False)
    os.replace(tmp, STORE)          # never leave a half-written store behind


def group_for(draw, groups=None):
    key = "+".join(sorted(draw))
    return next((g for g in (groups if groups is not None else load())
                 if g.get("key") == key), None)


def add_suggestion(draw, name, idea, who):
    groups = load()
    what, _how, cost, tier, how = reading_of(draw)
    group = group_for(draw, groups)
    if group is None:
        group = {"key": "+".join(sorted(draw)), "runes": draw,
                 "today": what, "how": how, "prayer": cost, "tier": tier,
                 "answers": []}
        groups.append(group)
    group["answers"].append({"name": name, "body": idea, "who": who,
                             "seconds": 0, "at": int(time.time())})
    save(groups)
    return group


## The commands ---------------------------------------------------------------

def cmd_runes(_args, _who):
    lines = ["**The ten rudiments**, taught a tier at a time:"]
    for i, tier in enumerate(BOOK.tiers, 1):
        lines.append("`tier %d`  %s" % (i, "  ".join(
            "**%s** (%s)" % (r, pretty(BOOK.base[r])) for r in tier)))
    lines.append("\nTry `%stable fire water`, then `%ssuggest fire water | "
                 "Quenching Rain | puts out every fire it touches`."
                 % (PREFIX, PREFIX))
    return "\n".join(lines), None


def cmd_table(args, _who):
    draw = parse_runes(args)
    line = today_line(draw)
    group = group_for(draw)
    if group and group["answers"]:
        line += "\n%d suggestion(s) so far — `%sboard %s`" % (
            len(group["answers"]), PREFIX, " ".join(draw))
    else:
        line += "\nNothing suggested for it yet."
    return line, None


def cmd_suggest(args, who):
    parts = [p.strip() for p in args.split("|")]
    if len(parts) < 3:
        raise ValueError(
            "Three parts, separated by `|`:\n"
            "`%ssuggest fire water | Quenching Rain | puts out every fire it "
            "touches, and the ground stays too wet to catch again`" % PREFIX)
    draw = parse_runes(parts[0])
    name, idea = parts[1], " | ".join(parts[2:]).strip()
    if not name or not idea:
        raise ValueError("It needs both a name and an idea.")
    if len(name) > NAME_MAX:
        raise ValueError(
            "That name is %d characters and a Discord poll answer holds %d."
            " Shorten it and the vote can use it exactly as you wrote it."
            % (len(name), NAME_MAX))
    group = add_suggestion(draw, name, idea[:IDEA_MAX], who)
    return ("%s\n\n**%s** — %s\n_put forward by %s · %d for this drawing so far_"
            % (today_line(draw), name, idea[:IDEA_MAX], who,
               len(group["answers"]))), None


def cmd_board(args, _who):
    draw = parse_runes(args)
    group = group_for(draw)
    if not group or not group["answers"]:
        return "Nothing put forward for **%s** yet." % drawing_line(draw), None
    lines = [today_line(draw), ""]
    for a in group["answers"][:15]:
        lines.append("**%s** — %s\n_%s_" % (a["name"], a["body"][:250],
                                            a.get("who", "?")))
    if len(group["answers"]) > 15:
        lines.append("_…and %d more._" % (len(group["answers"]) - 15))
    return "\n".join(lines), None


def cmd_poll(args, _who):
    """Hands back a Discord Poll Create Request object alongside the message.

    Shape per Discord's Poll and Webhook docs: `question.text`,
    `answers[].poll_media.text`, `duration` in hours, `allow_multiselect`.
    """
    bits = args.split("|")
    draw = parse_runes(bits[0])
    hours = 72
    if len(bits) > 1 and bits[1].strip().isdigit():
        hours = max(1, min(int(bits[1].strip()), 768))
    group = group_for(draw)
    if not group or not group["answers"]:
        return "Nothing to vote on for **%s** yet." % drawing_line(draw), None

    answers = group["answers"][:ANSWERS_MAX]
    dropped = len(group["answers"]) - len(answers)
    what, _how, cost, _tier, _ = reading_of(draw)
    question = ("What should %s do? Today %s %s, %d prayer."
                % (drawing_line(draw), ARROW, what, cost))[:300]
    poll = {
        "question": {"text": question},
        "answers": [{"poll_media": {"text": a["name"][:NAME_MAX]}}
                    for a in answers],
        "duration": hours,
        "allow_multiselect": False,
    }
    # The case for each name goes in the message, because a poll answer has
    # room for a name and nothing else, and the reasoning is the arguable part.
    note = "\n".join("**%s** — %s _(%s)_"
                     % (a["name"], a["body"][:200], a.get("who", "?"))
                     for a in answers)
    if dropped:
        note += ("\n_%d further suggestion(s) are not on the ballot — a Discord"
                 " poll holds %d._" % (dropped, ANSWERS_MAX))
    return note, poll


COMMANDS = {
    "runes": cmd_runes, "table": cmd_table, "suggest": cmd_suggest,
    "board": cmd_board, "poll": cmd_poll,
}


def handle(text, who):
    """Returns (reply, poll) or (None, None) if this was not for us."""
    if not text.startswith(PREFIX):
        return None, None
    body = text[len(PREFIX):].strip()
    if not body:
        return None, None
    word, _, args = body.partition(" ")
    fn = COMMANDS.get(word.lower())
    if fn is None:
        return None, None
    try:
        return fn(args.strip(), who)
    except ValueError as err:
        return str(err), None


## The loop -------------------------------------------------------------------

def main():
    token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    channel = os.environ.get("DISCORD_CHANNEL_ID", "").strip()
    if not token:
        raise SystemExit(
            "No token. Set DISCORD_BOT_TOKEN.\n\n"
            "  discord.com/developers/applications -> your app -> Bot\n"
            "  -> Reset Token -> copy it (Discord shows it once)\n\n"
            "  export DISCORD_BOT_TOKEN='…'\n\n"
            "Treat it as a password. If it ever leaks, Reset Token again and\n"
            "the old one stops working immediately.")
    if not channel.isdigit():
        raise SystemExit(
            "No channel. Set DISCORD_CHANNEL_ID to the channel it should watch.\n\n"
            "  Discord -> Settings -> Advanced -> Developer Mode ON,\n"
            "  then right-click the channel -> Copy Channel ID.\n\n"
            "  export DISCORD_CHANNEL_ID='…'")

    me = call(token, "GET", "/users/@me")
    if not me:
        raise SystemExit("Could not ask Discord who this token belongs to.")
    print("The council is sitting as %s#%s."
          % (me.get("username", "?"), me.get("discriminator", "0")))

    # Start from NOW, not from the beginning of the channel: nobody wants the
    # bot replying to three weeks of scrollback when it starts.
    recent = call(token, "GET", "/channels/%s/messages?limit=1" % channel)
    if recent is None:
        raise SystemExit(
            "Could not read that channel. Check the channel id, that the bot\n"
            "was invited to this server, and that it has Read Message History\n"
            "there. If the id is right, the usual cause is the Message Content\n"
            "Intent still being off in the Developer Portal (Bot tab).")
    after = recent[0]["id"] if recent else "0"

    print("Listening in channel %s. Commands: %s"
          % (channel, ", ".join(PREFIX + c for c in COMMANDS)))
    print("Suggestions are written to %s" % STORE)
    print("Ctrl-C to stop.\n")
    say(token, channel,
        "The council is sitting. `%srunes` for the alphabet, `%stable fire water`"
        " to see what a drawing does today." % (PREFIX, PREFIX))

    quiet = 0
    while True:
        try:
            time.sleep(POLL_EVERY)
            msgs = call(token, "GET", "/channels/%s/messages?after=%s&limit=50"
                        % (channel, after))
            if not msgs:
                continue
            # Discord hands these back newest-first; walk them oldest-first so
            # a burst of commands is answered in the order it was typed.
            msgs = sorted(msgs, key=lambda m: int(m["id"]))
            after = msgs[-1]["id"]
            for m in msgs:
                if (m.get("author") or {}).get("bot"):
                    continue        # never answer ourselves, or another bot
                text = (m.get("content") or "").strip()
                who = ((m.get("member") or {}).get("nick")
                       or (m.get("author") or {}).get("global_name")
                       or (m.get("author") or {}).get("username") or "someone")
                reply, poll = handle(text, who)
                if reply is None and poll is None:
                    continue
                if not text.startswith(PREFIX + "suggest"):
                    print("  %s: %s" % (who, text[:70]))
                else:
                    print("  %s suggested something" % who)
                say(token, channel, reply, poll)
            quiet = 0
        except KeyboardInterrupt:
            print("\nThe council rises. %d drawing(s) in %s."
                  % (len(load()), STORE))
            return 0
        except Exception as err:          # never let one bad message stop it
            quiet += 1
            print("  trouble: %s" % err, file=sys.stderr)
            if quiet > 20:
                raise SystemExit("Too many failures in a row; stopping.")


if __name__ == "__main__":
    raise SystemExit(main())
