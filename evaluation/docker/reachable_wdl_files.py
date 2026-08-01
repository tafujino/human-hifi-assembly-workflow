#!/usr/bin/env python3
"""Prints, one per line, the absolute path of every .wdl file reachable via `import`
from a given entry workflow (default: evaluation/workflows/assembly_evaluation.wdl,
the only file under evaluation/workflows/*.wdl that declares a top-level `workflow`).

Used by check_images.sh --list-reachable to narrow image enumeration to files a real
run can actually invoke. This matters because workflows/imports/ (the vendored flagger
and calN50 submodules) also contains standalone components this project's call graph
never imports -- e.g. flagger's DeepVariant/PEPPER-Margin-DeepVariant variant-calling
workflows, or its whole QC/assembly task library under ext/hpp_production_workflows --
so scanning the whole directory would report images this run never invokes.

Uses miniwdl's own import resolution (the `WDL` package) rather than hand-rolled
regex-following of `import` statements, since miniwdl is already a tool this project
assumes is available (see evaluation/docs/pipeline.md's `miniwdl input_template` step).

Usage:
  evaluation/docker/reachable_wdl_files.py [entry.wdl]
"""
import sys
from pathlib import Path

try:
    import WDL
except ImportError:
    print(
        "error: the `WDL` package (miniwdl) is required for this script -- "
        "pip install miniwdl and retry.",
        file=sys.stderr,
    )
    sys.exit(1)

DEFAULT_ENTRY = Path(__file__).resolve().parent.parent / "workflows" / "assembly_evaluation.wdl"


def collect(doc, seen):
    path = doc.pos.abspath
    if path in seen:
        return
    seen.add(path)
    for imp in doc.imports:
        if imp.doc is not None:
            collect(imp.doc, seen)


def main():
    entry = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_ENTRY
    entry_doc = WDL.load(str(entry), path=[])
    seen = set()
    collect(entry_doc, seen)
    for path in sorted(seen):
        print(path)


if __name__ == "__main__":
    main()
