#!/usr/bin/env python3
"""THE RUNE COUNCIL BOT — suggestions and polls, without anyone leaving Discord.

    /table   fire water            what that drawing does TODAY
    /suggest fire water …          put forward what it should do instead
    /board   fire water            everything put forward for it so far
    /poll    fire water            turn those into a real Discord poll

NO WEBHOOK ANYWHERE. A webhook URL is a bearer credential with no revocation
short of deleting it, and it has to be pasted into whatever posts with it. The
bot's token is a credential too — but it lives in one environment variable on
one machine, it is reset in two clicks if it ever leaks, and NOBODY TAKING PART
EVER TOUCHES IT. They type a slash command; that is the whole interface.

IT DOES NOT NEED HOSTING. Run it from your laptop while the group is working
and stop it afterwards. `/suggest` writes to a JSON file next to this script,
so nothing is lost when it stops, and the file is the same shape the
suggestion page exports and `discord_poll.py` reads — one pipeline, three ways
in.

WHAT IT SHOWS PEOPLE. Every reply carries the drawing's CURRENT reading, taken
from spellbook.gd through miracle_audit.py, so a suggestion is always made
against what the combination really does rather than what anyone remembers.

SETUP, once:

  1. discord.com/developers/applications -> New Application -> name it.
  2. Bot (left sidebar) -> Reset Token -> copy it. Discord shows it ONCE.
     No privileged intents are needed: this bot only uses slash commands and
     never reads message text.
  3. OAuth2 -> URL Generator -> scopes `bot` AND `applications.commands`,
     bot permission `Send Messages`. Open the URL, pick your server.
  4. In Discord, right-click your server -> Copy Server ID. (Turn on
     Settings -> Advanced -> Developer Mode first if you do not see it.)

Then:

    pip install -U discord.py
    export DISCORD_BOT_TOKEN='…'      # never paste this anywhere else
    export DISCORD_GUILD_ID='…'
    python3 tools/rune_bot.py

Commands appear in that server within seconds. Ctrl-C to stop.
"""
import datetime
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

try:
    import discord
    from discord import app_commands
except ImportError:
    raise SystemExit(
        "discord.py is not installed.\n\n    pip install -U discord.py\n\n"
        "It is the only dependency this repository has; everything else here\n"
        "runs on the standard library.")

import miracle_audit

BOOK = miracle_audit.Book()
STORE = os.path.join(HERE, "suggestions.json")

NAME_MAX = 55        # Discord's cap on a poll answer, so also on a name
IDEA_MAX = 400
ANSWERS_MAX = 10     # Discord's cap on poll answers
ARROW = "▸"


## Reading a drawing ----------------------------------------------------------

def parse_runes(text):
    """'fire water' or 'fire+water' or 'Fire, Water' -> ['fire', 'water'].

    Raises ValueError naming the offending word, because 'that is not a rune'
    with no clue which one is a genuinely annoying thing to be told.
    """
    words = [w.strip().lower() for w in
             text.replace("+", " ").replace(",", " ").split()]
    words = [w for w in words if w]
    if not words:
        raise ValueError("Name at least one rune.")
    if len(words) > 6:
        raise ValueError("Six runes is more than anyone will ever draw at once.")
    for w in words:
        if w not in BOOK.base:
            raise ValueError("`%s` is not a rune. They are: %s."
                             % (w, ", ".join(BOOK.runes)))
    return words


def pretty(miracle):
    return miracle.replace("_", " ").title()


def reading_of(draw):
    """One line saying what the drawing does today, and one saying how."""
    r = BOOK.interpret(draw)
    cost = round(BOOK.cost(draw))
    tier = BOOK.tier_needed(draw)
    if r["how"] == "NAMED":
        what = "**%s**" % pretty(r["miracle"])
        how = "a named miracle, written by hand"
    elif r["how"] == "AMPLIFIED":
        what = "**%s**, at %.2f× potency" % (pretty(r["miracle"]), r["potency"])
        how = "one rune repeated: the same miracle writ larger"
    else:
        parts = ", ".join("%s ×%.2f" % (pretty(m), p) for m, p in r["parts"])
        what = "no name of its own — %s" % parts
        how = ("a multi-cast: every rune's miracle at once, each weakened."
               " Four fifths of the spellbook lands here.")
    return (what, how, cost, tier, r["how"])


def drawing_line(draw):
    return " + ".join(draw)


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


def add_suggestion(draw, name, idea, who):
    groups = load()
    key = "+".join(sorted(draw))
    what, _how, cost, tier, how = reading_of(draw)
    group = next((g for g in groups if g.get("key") == key), None)
    if group is None:
        group = {"key": key, "runes": draw,
                 "today": what.replace("**", ""), "how": how,
                 "prayer": cost, "tier": tier, "answers": []}
        groups.append(group)
    group["answers"].append({"name": name, "body": idea, "who": who,
                             "seconds": 0, "at": int(time.time())})
    save(groups)
    return group


def group_for(draw):
    key = "+".join(sorted(draw))
    return next((g for g in load() if g.get("key") == key), None)


## The bot --------------------------------------------------------------------

GUILD_ID = os.environ.get("DISCORD_GUILD_ID", "").strip()
GUILD = discord.Object(id=int(GUILD_ID)) if GUILD_ID.isdigit() else None


class Council(discord.Client):
    def __init__(self):
        # Slash commands need no privileged intents at all — this bot never
        # reads message content and never looks at the member list.
        super().__init__(intents=discord.Intents.default())
        self.tree = app_commands.CommandTree(self)

    async def setup_hook(self):
        # Copied to ONE guild and synced there: guild commands appear within
        # seconds, where a global sync can take an hour to propagate.
        if GUILD is not None:
            self.tree.copy_global_to(guild=GUILD)
            await self.tree.sync(guild=GUILD)
        else:
            await self.tree.sync()


client = Council()


def embed_for(draw, title, colour):
    what, how, cost, tier, _ = reading_of(draw)
    e = discord.Embed(title=title, colour=colour)
    e.add_field(name="Today", value="%s\n_%s_" % (what, how), inline=False)
    e.add_field(name="Prayer", value=str(cost))
    e.add_field(name="Tier", value=str(tier))
    return e


@client.tree.command(description="What does a drawing do right now?")
@app_commands.describe(runes="e.g. fire water")
async def table(interaction, runes: str):
    try:
        draw = parse_runes(runes)
    except ValueError as err:
        await interaction.response.send_message(str(err), ephemeral=True)
        return
    e = embed_for(draw, drawing_line(draw), 0xA97C1B)
    group = group_for(draw)
    if group:
        e.set_footer(text="%d suggestion(s) so far — /board to read them"
                     % len(group["answers"]))
    else:
        e.set_footer(text="Nothing suggested for it yet — /suggest")
    await interaction.response.send_message(embed=e)


@client.tree.command(description="Put forward what a drawing should do")
@app_commands.describe(runes="e.g. fire water",
                       name="a short name — 55 characters, Discord's poll limit",
                       idea="what it should actually do")
async def suggest(interaction, runes: str, name: str, idea: str):
    try:
        draw = parse_runes(runes)
    except ValueError as err:
        await interaction.response.send_message(str(err), ephemeral=True)
        return
    name, idea = name.strip(), idea.strip()
    if not name or not idea:
        await interaction.response.send_message(
            "It needs both a name and an idea.", ephemeral=True)
        return
    if len(name) > NAME_MAX:
        await interaction.response.send_message(
            "That name is %d characters and a Discord poll answer holds %d."
            " Shorten it and the vote can use it as it stands."
            % (len(name), NAME_MAX), ephemeral=True)
        return
    idea = idea[:IDEA_MAX]

    who = getattr(interaction.user, "display_name", str(interaction.user))
    group = add_suggestion(draw, name, idea, who)

    e = embed_for(draw, "%s %s %s" % (drawing_line(draw), ARROW, name), 0x3F7A57)
    e.add_field(name="Should be", value=idea, inline=False)
    e.set_footer(text="put forward by %s · %d for this drawing so far"
                 % (who, len(group["answers"])))
    # Posted openly rather than quietly: the point of doing this in Discord is
    # that everyone sees what everyone else thought of.
    await interaction.response.send_message(embed=e)


@client.tree.command(description="Everything put forward for a drawing")
@app_commands.describe(runes="e.g. fire water")
async def board(interaction, runes: str):
    try:
        draw = parse_runes(runes)
    except ValueError as err:
        await interaction.response.send_message(str(err), ephemeral=True)
        return
    group = group_for(draw)
    if not group or not group["answers"]:
        await interaction.response.send_message(
            "Nothing put forward for %s yet." % drawing_line(draw))
        return
    e = embed_for(draw, "%s — %d suggestion(s)"
                  % (drawing_line(draw), len(group["answers"])), 0x4A6E8A)
    for a in group["answers"][:20]:
        e.add_field(name=a["name"][:256],
                    value="%s\n_%s_" % (a["body"][:900], a.get("who", "?")),
                    inline=False)
    await interaction.response.send_message(embed=e)


@client.tree.command(description="Turn a drawing's suggestions into a poll")
@app_commands.describe(runes="e.g. fire water",
                       hours="how long the poll runs (1-768, default 72)",
                       multi="let people pick more than one")
async def poll(interaction, runes: str, hours: int = 72, multi: bool = False):
    try:
        draw = parse_runes(runes)
    except ValueError as err:
        await interaction.response.send_message(str(err), ephemeral=True)
        return
    if not hasattr(discord, "Poll"):
        await interaction.response.send_message(
            "This discord.py is too old to make polls. `pip install -U discord.py`",
            ephemeral=True)
        return
    group = group_for(draw)
    if not group or not group["answers"]:
        await interaction.response.send_message(
            "Nothing to vote on for %s yet." % drawing_line(draw), ephemeral=True)
        return

    answers = group["answers"][:ANSWERS_MAX]
    dropped = len(group["answers"]) - len(answers)
    what, _how, cost, _tier, _ = reading_of(draw)
    question = "What should %s do? Today %s %s, %d prayer." % (
        drawing_line(draw), ARROW, what.replace("**", ""), cost)

    p = discord.Poll(question=question[:300],
                     duration=datetime.timedelta(
                         hours=max(1, min(int(hours), 768))),
                     multiple=bool(multi))
    for a in answers:
        p.add_answer(text=a["name"][:NAME_MAX])

    note = "\n".join("**%s** — %s _(%s)_"
                     % (a["name"], a["body"][:220], a.get("who", "?"))
                     for a in answers)
    if dropped:
        note += "\n\n_%d further suggestion(s) not on the ballot — a Discord" \
                " poll holds %d._" % (dropped, ANSWERS_MAX)
    await interaction.response.send_message(content=note[:1900], poll=p)


@client.event
async def on_ready():
    where = "guild %s" % GUILD_ID if GUILD else "globally (may take an hour)"
    print("The council is sitting as %s — commands registered %s."
          % (client.user, where))
    print("Suggestions are written to %s" % STORE)


def main():
    token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    if not token:
        raise SystemExit(
            "No token. Set DISCORD_BOT_TOKEN.\n\n"
            "  discord.com/developers/applications -> your app -> Bot\n"
            "  -> Reset Token -> copy it (Discord shows it once)\n\n"
            "  export DISCORD_BOT_TOKEN='…'\n\n"
            "Treat it as a password. If it ever leaks, Reset Token again and\n"
            "the old one stops working immediately.")
    if not GUILD:
        print("No DISCORD_GUILD_ID set — syncing commands globally, which can\n"
              "take up to an hour to appear. Set it for an instant sync.",
              file=sys.stderr)
    client.run(token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
