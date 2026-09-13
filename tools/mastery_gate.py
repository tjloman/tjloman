#!/usr/bin/env python3
"""NO QUEST MAY EVER GATE ON WHETHER THE PLAYER WAS GOOD.

The design rule, in the author's own words: at any time the player can start
teaching their creature to prefer eating babies, burn everything it can, and
sleep only under water. The introduction teaches the MECHANICS and demands a
demonstration of each; it never demands that the demonstration was kind.

That distinction is one word wide in a beat and very easy to cross by accident:

    "until": func() -> bool: return who.lessons > was          # mechanics. fine.
    "until": func() -> bool: return who.morality > 0.0         # a moral gate.

The second one reads perfectly reasonably while you are writing it, passes every
other check in this repository, and quietly makes a whole style of play into a
dead end — the player who is raising a monster simply stops being able to
continue, and nothing tells them why.

So: a beat's `until`, and the `skip`/`or` conditions if those ever exist, may not
read anything that measures the creature's character or the god's. Everything
else about a creature is fair game — what it has learned, what it can do, what it
is carrying, how big it is, whether it is on a lead.

Run with --check to fail the build.
"""
import os
import re
import sys

BOARDS = "scripts/story"

# What "was the player good" looks like, whatever it is spelled on.
MORAL = (
    "morality", "temperament", "alignment", "shift_alignment",
    "ethos", "kindness", "conscience", "is_wicked", "is_saintly",
    "grudge", "hates_creature", "karma",
)
# The keys of a beat that DECIDE whether the player may go on. `do` and `then`
# may do anything they like — they are consequences, not gates.
GATES = ("until", "skip", "or")


def beats(text):
    """(line number, gate key, the expression) for every gate in a board."""
    out = []
    for i, line in enumerate(text.split("\n"), 1):
        code = line.split("#", 1)[0]
        for key in GATES:
            m = re.search(r'"%s"\s*:\s*(.*)$' % key, code)
            if m:
                out.append((i, key, m.group(1)))
    return out


def main():
    problems = []
    if not os.path.isdir(BOARDS):
        print("no storyboards yet — nothing to check")
        return 0
    checked = 0
    for name in sorted(os.listdir(BOARDS)):
        if not name.endswith(".gd"):
            continue
        path = os.path.join(BOARDS, name)
        text = open(path, encoding="utf-8").read()
        lines = text.split("\n")
        for lineno, key, expr in beats(text):
            checked += 1
            # A gate's body may run on past its own line; take the rest of the
            # beat, up to the next key or the closing brace.
            body = expr
            for nxt in lines[lineno:lineno + 6]:
                if re.match(r'\s*("(\w+)"\s*:|\})', nxt):
                    break
                body += " " + nxt.split("#", 1)[0]
            for word in MORAL:
                if re.search(r"(?<![\w.])%s(?![\w])" % word, body) \
                        or ("." + word) in body:
                    problems.append((path, lineno, key, word, expr.strip()))
    print("checked %d gate(s) across the storyboards" % checked)
    for path, lineno, key, word, expr in problems:
        print("%s:%d: this '%s' reads '%s' — a gate may ask whether the player "
              "can WORK a mechanic, never whether they used it kindly. A player "
              "raising a monster must be able to finish the introduction.\n    %s"
              % (path, lineno, key, word, expr))
    if problems:
        print("\n%d moral gate(s). The rule is in tools/mastery_gate.py."
              % len(problems))
        return 1
    print("No gate asks whether the player was good.")
    return 0


if __name__ == "__main__":
    code = main()
    sys.exit(code if "--check" in sys.argv else 0)
