#!/usr/bin/env python3
"""POST THE RUNE SUGGESTIONS TO DISCORD AS REAL POLLS.

One poll per drawing: the question names the combination and what it does
today, and the answers are the names people put forward for it, best-seconded
first. Discord counts the votes, so the focus group's afternoon comes back as
numbers rather than as a thread to be read.

WHY THIS IS A SCRIPT AND NOT PART OF THE PAGE. The suggestion page is a
published Artifact, and a published Artifact is sandboxed: it cannot call out
to any server, Discord included. That is the right way round anyway. A webhook
URL is a WRITE CREDENTIAL — anyone holding it can post to your channel until
you delete it — so it belongs in an environment variable on your machine and
never in a page you hand round. Pass it with --webhook or set DISCORD_WEBHOOK.

WHERE THE INPUT COMES FROM. The page's "Copy everything as JSON" button, saved
to a file. Its shape, which is also what --dry-run prints:

    [ { "key": "fire+water",
        "runes": ["fire", "water"],
        "today": "a working of your own (multi-cast)",
        "how": "BLEND", "prayer": 40, "tier": 3,
        "answers": [ {"name": "...", "body": "...",
                      "who": "...", "seconds": 4} ] } ]

DISCORD'S LIMITS, which this enforces rather than discovers at 400:
  question   300 characters
  answers    1-10 per poll, 55 characters each
  duration   1-768 hours (32 days), 24 if unset
Anything over the answer limit is truncated with an ellipsis and reported;
anything past ten answers is dropped, best-seconded kept.

Usage:
    python3 tools/discord_poll.py suggestions.json --dry-run
    python3 tools/discord_poll.py suggestions.json --webhook "$DISCORD_WEBHOOK"
    python3 tools/discord_poll.py suggestions.json --hours 72 --multi
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

QUESTION_MAX = 300
ANSWER_MAX = 55
ANSWERS_MAX = 10
HOURS_MIN, HOURS_MAX = 1, 768

## The runes as a reader of the channel will see them. Discord renders no SVG
## in a poll, so the drawing is spelled out — and the arrow is what the game's
## own readout uses between a drawing and its reading.
ARROW = "▸"


def clip(text, limit):
    """Truncate on a word boundary where one is close to the limit."""
    text = " ".join(str(text).split())
    if len(text) <= limit:
        return text, False
    cut = text[:limit - 1]
    if " " in cut[int(limit * 0.6):]:
        cut = cut[:cut.rindex(" ")]
    return cut + "…", True


def question_for(group):
    drawing = " + ".join(group.get("runes") or group["key"].split("+"))
    today = group.get("today", "nothing named")
    prayer = group.get("prayer")
    tail = ", %d prayer." % prayer if isinstance(prayer, (int, float)) else "."
    q = "What should %s do? Today %s %s%s" % (drawing, ARROW, today, tail)
    return clip(q, QUESTION_MAX)[0]


def poll_for(group, hours, multi):
    """A Discord Poll Create Request object.

    Shape per Discord's Poll and Webhook resource docs: `poll.question.text`,
    `poll.answers[].poll_media.text`, `duration` in hours, `allow_multiselect`.
    """
    answers, trimmed = [], []
    ranked = sorted(group.get("answers", []),
                    key=lambda a: (-int(a.get("seconds", 0) or 0),
                                   str(a.get("name", ""))))
    for a in ranked[:ANSWERS_MAX]:
        text, cut = clip(a.get("name", ""), ANSWER_MAX)
        if not text:
            continue
        if cut:
            trimmed.append(a.get("name", ""))
        answers.append({"poll_media": {"text": text}})
    dropped = max(0, len(ranked) - ANSWERS_MAX)
    return {
        "poll": {
            "question": {"text": question_for(group)},
            "answers": answers,
            "duration": max(HOURS_MIN, min(int(hours), HOURS_MAX)),
            "allow_multiselect": bool(multi),
        }
    }, trimmed, dropped


def body_note(group):
    """The reasoning, as a plain message under the poll — a poll answer has
    room for a name and nothing else, and the case for it is the part worth
    arguing with."""
    lines = []
    ranked = sorted(group.get("answers", []),
                    key=lambda a: -int(a.get("seconds", 0) or 0))
    for a in ranked[:ANSWERS_MAX]:
        name, _ = clip(a.get("name", ""), ANSWER_MAX)
        body, _ = clip(a.get("body", ""), 300)
        who = str(a.get("who", "") or "anonymous")
        seconds = int(a.get("seconds", 0) or 0)
        second = " · %d seconded" % seconds if seconds else ""
        lines.append("**%s** — %s\n_%s%s_" % (name, body, who, second))
    return "\n\n".join(lines)[:1900]


def post(webhook, payload, retries=4):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        webhook + ("&" if "?" in webhook else "?") + "wait=true",
        data=data, method="POST",
        headers={"Content-Type": "application/json",
                 "User-Agent": "hand-of-the-heavens-poll/1.0"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8") or "{}")
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:400]
            # 429 is Discord's rate limit and carries how long to wait for.
            if e.code == 429 and attempt < retries - 1:
                wait = 2.0 * (attempt + 1)
                try:
                    wait = float(json.loads(detail).get("retry_after", wait))
                except Exception:
                    pass
                print("  rate limited; waiting %.1fs" % wait, file=sys.stderr)
                time.sleep(wait)
                continue
            raise SystemExit("Discord refused the post (HTTP %d): %s"
                             % (e.code, detail))
        except urllib.error.URLError as e:
            if attempt < retries - 1:
                time.sleep(2.0 * (attempt + 1))
                continue
            raise SystemExit("Could not reach Discord: %s" % e.reason)
    return {}


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", help="JSON from the suggestion page")
    ap.add_argument("--webhook", default=os.environ.get("DISCORD_WEBHOOK", ""),
                    help="Discord webhook URL (or set DISCORD_WEBHOOK)")
    ap.add_argument("--dry-run", action="store_true",
                    help="print exactly what would be posted, and post nothing")
    ap.add_argument("--hours", type=int, default=72,
                    help="how long each poll runs, 1-768 (default 72)")
    ap.add_argument("--multi", action="store_true",
                    help="let people pick more than one answer")
    ap.add_argument("--only", action="append", default=[],
                    help="post just this drawing, e.g. --only fire+water")
    ap.add_argument("--no-notes", action="store_true",
                    help="post the polls without the message of reasoning")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8") as fh:
        groups = json.load(fh)
    if isinstance(groups, dict):
        groups = [groups]
    if args.only:
        wanted = {k.strip() for k in args.only}
        groups = [g for g in groups if g.get("key") in wanted]
    groups = [g for g in groups if g.get("answers")]
    if not groups:
        raise SystemExit("Nothing to post: no drawing in that file has answers.")

    if not args.dry_run and not args.webhook:
        raise SystemExit(
            "No webhook. Pass --webhook or set DISCORD_WEBHOOK.\n"
            "In Discord: Server Settings > Integrations > Webhooks > New.\n"
            "Treat the URL as a password — anyone holding it can post to that\n"
            "channel. Use --dry-run first to see exactly what would be sent.")

    print("%d drawing(s), %d poll(s) to post, %d hours each%s\n"
          % (len(groups), len(groups), args.hours,
             ", multiselect" if args.multi else ""))

    for g in groups:
        payload, trimmed, dropped = poll_for(g, args.hours, args.multi)
        poll = payload["poll"]
        if not poll["answers"]:
            print("  %-24s skipped: no usable answers" % g.get("key", "?"))
            continue
        if not args.no_notes:
            payload["content"] = body_note(g)

        print("  %s" % poll["question"]["text"])
        for i, a in enumerate(poll["answers"], 1):
            print("    %2d. %s" % (i, a["poll_media"]["text"]))
        for name in trimmed:
            print("    ! trimmed to %d characters: %s" % (ANSWER_MAX, name))
        if dropped:
            print("    ! %d further suggestion(s) dropped — Discord allows %d"
                  % (dropped, ANSWERS_MAX))

        if args.dry_run:
            print()
            continue
        msg = post(args.webhook, payload)
        print("    posted, message %s\n" % msg.get("id", "?"))
        time.sleep(1.0)          # gentle with the channel's rate limit

    if args.dry_run:
        print("Dry run — nothing was posted. Add --webhook to send it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
