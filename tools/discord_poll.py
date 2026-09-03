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

READING THE VOTES BACK. Posting records a ledger of message ids beside the
input; `--results` reads each poll's running tally through Get Webhook Message
and writes it as JSON. Discord counts approximately while a poll is open and
does one exact tally after it closes — `is_finalized` says which you have, and
the report says so too, because it matters to anyone deciding from the number.

Usage:
    python3 tools/discord_poll.py suggestions.json --dry-run
    python3 tools/discord_poll.py suggestions.json --webhook "$DISCORD_WEBHOOK"
    python3 tools/discord_poll.py suggestions.json --hours 72 --multi
    python3 tools/discord_poll.py suggestions.posted.json --results
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


def fetch(webhook, message_id):
    """Get Webhook Message — the poll comes back with its running tally in
    `poll.results.answer_counts`. Apps cannot vote and cannot close a poll, so
    reading is all there is to do from here."""
    url = "%s/messages/%s" % (webhook.rstrip("/"), message_id)
    req = urllib.request.Request(
        url, headers={"User-Agent": "hand-of-the-heavens-poll/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:200]
        print("  could not read %s (HTTP %d): %s" % (message_id, e.code, detail),
              file=sys.stderr)
        return None
    except urllib.error.URLError as e:
        print("  could not reach Discord: %s" % e.reason, file=sys.stderr)
        return None


def show_results(webhook, ledger_path):
    """Read every poll named in a ledger and print the tally.

    Discord counts approximately while a poll runs and does a final exact
    tally after it closes; `is_finalized` says which you are looking at, and
    that distinction is worth keeping in front of anyone about to make a
    decision from these numbers.
    """
    with open(ledger_path, encoding="utf-8") as fh:
        ledger = json.load(fh)
    out = []
    for entry in ledger:
        msg = fetch(webhook, entry["message_id"])
        if msg is None:
            # NOT the same as no votes, and must never be printed as if it
            # were: nobody should read a failed request as a result of zero.
            print("\n  %s — could not be read; no tally for it here"
                  % entry["key"])
            out.append({"key": entry["key"], "message_id": entry["message_id"],
                        "read": False})
            continue
        poll = msg.get("poll") or {}
        results = poll.get("results") or {}
        counts = {int(c["id"]): int(c["count"])
                  for c in results.get("answer_counts", [])}
        answers = poll.get("answers", [])
        rows = []
        for a in answers:
            aid = int(a.get("answer_id", 0))
            rows.append({"answer": (a.get("poll_media") or {}).get("text", ""),
                         "votes": counts.get(aid, 0)})
        rows.sort(key=lambda r: -r["votes"])
        total = sum(r["votes"] for r in rows)
        final = bool(results.get("is_finalized"))

        print("\n  %s" % (poll.get("question") or {}).get("text", entry["key"]))
        print("  %s, %d vote(s)%s" % (
            entry["key"], total,
            "" if final else "  — still open, counted approximately"))
        for r in rows:
            share = (100.0 * r["votes"] / total) if total else 0.0
            bar = "#" * int(round(share / 4))
            print("    %5d  %3.0f%%  %-22s %s" % (r["votes"], share, bar, r["answer"]))
        out.append({"key": entry["key"], "message_id": entry["message_id"],
                    "read": True, "finalized": final, "total": total,
                    "answers": rows})
    return out


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
    ap.add_argument("--ledger", default="",
                    help="where the posted message ids are written"
                         " (default: alongside the input, .posted.json)")
    ap.add_argument("--results", action="store_true",
                    help="read the votes back for polls in the ledger and stop")
    args = ap.parse_args()

    ledger_path = args.ledger or (args.file.rsplit(".", 1)[0] + ".posted.json")

    # READING THE VOTES BACK. The file argument is the ledger in this mode.
    if args.results:
        if not args.webhook:
            raise SystemExit("Reading votes needs the webhook too:"
                             " --webhook or DISCORD_WEBHOOK.")
        path = args.file if args.file.endswith(".posted.json") else ledger_path
        try:
            tally = show_results(args.webhook, path)
        except FileNotFoundError:
            raise SystemExit("No ledger at %s — post the polls first." % path)
        with open(path.replace(".posted.json", ".results.json"), "w",
                  encoding="utf-8") as fh:
            json.dump(tally, fh, indent=1)
        print("\n  written to %s"
              % path.replace(".posted.json", ".results.json"))
        return 0

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

    posted = []
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
        if msg.get("id"):
            posted.append({"key": g.get("key", ""), "message_id": msg["id"]})
        time.sleep(1.0)          # gentle with the channel's rate limit

    if args.dry_run:
        print("Dry run — nothing was posted. Add --webhook to send it.")
        return 0
    if posted:
        # The ledger is the only record of which message holds which drawing's
        # poll, and --results cannot find the votes again without it.
        with open(ledger_path, "w", encoding="utf-8") as fh:
            json.dump(posted, fh, indent=1)
        print("Message ids written to %s — read the votes back later with\n"
              "  python3 tools/discord_poll.py %s --results --webhook ..."
              % (ledger_path, ledger_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
