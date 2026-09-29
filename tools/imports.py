#!/usr/bin/env python3
"""IMPORTS AT THE TOP, AND ONLY AT THE TOP.

"We need to keep our code tidy... let's put our import blocks at loadup."

Every tool here opens with its imports, one to a line, and a reader can see at
a glance what a file leans on. A few had drifted: `import random` inside the
function that first wanted it, `import ast` halfway down among the constants,
`import heapq` in a helper, a sibling tool imported from inside a check, and
three modules on one line. This reads every tool with Python's own parser and
refuses:

  * an import inside a function or class;
  * a module-level import after the first statement that is not an import —
    except the path setup a sibling-tool import needs (`sys.path.insert`) and
    the path it is built from (anything computed from `__file__`);
  * more than one module on one `import` line.

EXCUSED BY NAME, each for a reason: an optional heavy dependency imported only
on the path that needs it is not untidiness, it is what lets the file run
without it.
"""
import ast
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXCUSED = {
    # The river tool reads GeoTIFFs only when asked to; everything else in it
    # runs on a machine without rasterio installed.
    ("soundings.py", "rasterio"),
}


def _is_setup(node):
    """Statements allowed between imports: where this file is, the search path
    built from it, and nothing else — which is what importing a sibling tool
    takes (`HERE = ...(__file__)`, `sys.path.insert(0, HERE)`, `import x`)."""
    if isinstance(node, ast.Assign) and "__file__" in ast.unparse(node.value):
        return True
    if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
        text = ast.unparse(node.value)
        return text.startswith("sys.path.insert(") or text.startswith("sys.path.append(")
    return False


def check(path, fail):
    tree = ast.parse(path.read_text(), filename=str(path))
    body = tree.body
    if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant):
        body = body[1:]                      # the docstring
    past_top = False
    for node in body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            if past_top:
                fail.append("%s:%d imports below the top of the file"
                            % (path.name, node.lineno))
            if isinstance(node, ast.Import) and len(node.names) > 1:
                fail.append("%s:%d imports %d modules on one line"
                            % (path.name, node.lineno, len(node.names)))
        elif not _is_setup(node):
            past_top = True
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        for inner in ast.walk(node):
            if isinstance(inner, (ast.Import, ast.ImportFrom)):
                names = [a.name for a in inner.names] if isinstance(inner, ast.Import) \
                    else [inner.module or ""]
                if all((path.name, n) in EXCUSED for n in names):
                    continue
                fail.append("%s:%d imports %s inside %s()"
                            % (path.name, inner.lineno, ", ".join(names), node.name))


def main():
    fail = []
    files = sorted((ROOT / "tools").glob("*.py"))
    for path in files:
        check(path, fail)
    print("%d tools read; imports at the top, one to a line." % len(files))
    print()
    if fail:
        for f in sorted(set(fail)):
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
