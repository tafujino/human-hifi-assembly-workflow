#!/usr/bin/env python3
"""Prints, one per line, the docker image actually used by every task reachable via the
*call graph* (not just the `import` graph) from a given entry workflow (default:
evaluation/workflows/assembly_evaluation.wdl).

Just following `import` statements (miniwdl's own import-closure resolution) would report
every `dockerImage`/`docker` default literal in every file the entry workflow's document tree
pulls in -- including tasks/workflows nothing in the actual call graph ever invokes (e.g.
flagger's DeepVariant/PEPPER-Margin-DeepVariant variant-calling workflows), and a task's own
hardcoded default even when every real call site overrides it (e.g. augmentCoverageByLabels's
`dockerImage` default is the unfixed upstream image, but every call in this project's actual
workflow passes `dockerImage = flaggerDockerImage`, which resolves to this fork's image).

This instead walks the actual `Call` graph via miniwdl's resolved AST (`Call.callee`,
`Ident.referee`) starting from the entry workflow, and for each task actually reachable,
resolves its `runtime.docker` expression by:
  - using the call site's override expression if the call provides one for that input,
    resolved recursively one scope further out if it's itself just a pass-through of an
    enclosing workflow input;
  - falling back to the task's own declared default otherwise.
Only plain string literals and simple identifier pass-throughs are resolved -- an expression
built from string interpolation, concatenation, or a conditional is reported as UNRESOLVED
(with its source text) rather than guessed at, since this project's own WDL files never
compute a docker image dynamically today, and a wrong guess would defeat the point of
resolving anything at all.

Usage:
  evaluation/docker/resolve_reachable_images.py [entry.wdl]
  evaluation/docker/resolve_reachable_images.py --verbose [entry.wdl]  # print task name too
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
UNRESOLVED = object()


def iter_body(body):
    """Flattens Scatter/Conditional nodes so their nested Calls are visited too."""
    for node in body:
        yield node
        inner = getattr(node, "body", None)
        if inner is not None:
            yield from iter_body(inner)


def resolve_expr(expr, scope_stack):
    """scope_stack: list of (task_or_workflow, invoking_call_or_None), innermost last.
    Returns a resolved string, or UNRESOLVED if the expression can't be statically decided."""
    if expr is None:
        return UNRESOLVED
    if isinstance(expr, WDL.Expr.String):
        return expr.literal.value if expr.literal is not None else UNRESOLVED
    if isinstance(expr, WDL.Expr.Get) and isinstance(expr.expr, WDL.Expr.Ident):
        decl = expr.expr.referee
        if decl is None:
            return UNRESOLVED
        scope, invoking_call = scope_stack[-1]
        is_input = decl in getattr(scope, "inputs", ())
        if is_input and invoking_call is not None and decl.name in invoking_call.inputs:
            # Overridden at the call site -- resolve that expression one scope further out.
            return resolve_expr(invoking_call.inputs[decl.name], scope_stack[:-1])
        # Not overridden (or a body-local decl, which callers can't override at all):
        # fall back to its own default expression, in the same scope.
        return resolve_expr(decl.expr, scope_stack)
    return UNRESOLVED


def walk(workflow, scope_stack, results, seen_calls):
    for node in iter_body(workflow.body):
        if not isinstance(node, WDL.Tree.Call):
            continue
        callee = node.callee
        new_stack = scope_stack + [(callee, node)]
        if isinstance(callee, WDL.Tree.Task):
            docker_expr = callee.runtime.get("docker")
            value = resolve_expr(docker_expr, new_stack)
            if value is UNRESOLVED:
                # Fall back to the task's own literal default in isolation (no call-site
                # override, no enclosing scope) rather than silently dropping this task from
                # the output -- e.g. still catches an unresolvable `dockerImage` input that
                # nonetheless has a plain literal default. Only genuinely dynamic defaults
                # (interpolated/computed) stay UNRESOLVED after this.
                value = resolve_expr(docker_expr, [(callee, None)])
            results.append((callee.name, value, docker_expr))
        elif isinstance(callee, WDL.Tree.Workflow):
            # Avoid re-walking (and re-reporting) the same sub-workflow callee+call-site
            # combination twice if it's reachable via more than one path.
            key = (id(callee), id(node))
            if key not in seen_calls:
                seen_calls.add(key)
                walk(callee, new_stack, results, seen_calls)


def main():
    args = [a for a in sys.argv[1:] if a != "--verbose"]
    verbose = "--verbose" in sys.argv[1:]
    entry = Path(args[0]) if args else DEFAULT_ENTRY

    entry_doc = WDL.load(str(entry), path=[])
    if entry_doc.workflow is None:
        print(f"error: {entry} declares no top-level workflow", file=sys.stderr)
        sys.exit(1)

    results = []
    walk(entry_doc.workflow, [(entry_doc.workflow, None)], results, set())

    resolved = set()
    for task_name, value, expr in results:
        if value is UNRESOLVED:
            print(f"UNRESOLVED\t{task_name}\t{expr}" if verbose else f"UNRESOLVED({task_name}): {expr}",
                  file=sys.stderr)
            continue
        resolved.add(value)
        if verbose:
            print(f"{value}\t{task_name}")

    if not verbose:
        for value in sorted(resolved):
            print(value)


if __name__ == "__main__":
    main()
