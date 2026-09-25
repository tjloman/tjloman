#!/usr/bin/env python3
"""A TOWN IS AS BIG AS ITS ROOFS — INCLUDING THE CHILDREN ON THE WAY.

Births stop when a town reaches its beds plus a little. That was asked at
CONCEPTION and counted only the born, so every pregnancy in flight when the limit
was reached still arrived: a town of five hundred reaching its limit with forty
mothers expecting took in forty more than it had beds for, three quarters of a
year later, every time. That is most of a street sleeping rough that no rule
ever let it have. This checks the limit counts them, and that the exact bed
count is on the hover card, where a screenshot cannot give it.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VILLAGE = (ROOT / "scripts/world/village.gd").read_text()
HOUSE = (ROOT / "scripts/world/house.gd").read_text()


def body(text, name):
    m = re.search(r"^func %s\(" % re.escape(name), text, re.M)
    rest = text[m.end():]
    nxt = re.search(r"^func ", rest, re.M)
    return "\n".join(l.split("#")[0] for l in (rest[:nxt.start()] if nxt else rest).splitlines())


def main():
    fail = []
    beds, slack, expecting = 500, 8, 40
    print("A TOWN AT ITS LIMIT WITH %d MOTHERS EXPECTING" % expecting)
    print("  born only:          ends at %d people in %d beds" % (beds + slack + expecting, beds))
    print("  born and expected:  ends at %d" % (beds + slack))
    if "_expecting" not in body(VILLAGE, "at_capacity"):
        fail.append("the birth limit counts only the born, so every pregnancy "
                    "in flight lands on top of it")
    else:
        print("  the limit counts the children on the way ........ yes")
    if "if v.pregnant:" not in body(VILLAGE, "_retally") \
            or "_expecting += 1" not in body(VILLAGE, "_retally"):
        fail.append("nothing counts the expecting mothers, so the limit is "
                    "reading a number that is always nought")
    if "housing_capacity()" not in body(HOUSE, "hover_text") \
            or "homeless_count()" not in body(HOUSE, "hover_text"):
        fail.append("the hover card no longer gives a town's exact beds and "
                    "homeless")
    else:
        print("  a house's card gives the town's exact beds ...... yes")
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
