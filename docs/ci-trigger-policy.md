# CI Trigger Policy — Documentation-Only Changes

## Status

**Design recorded; implementation deferred.** The current
`.github/workflows/p34-ci.yml` still runs on every `push` and `pull_request`.
This document records the selected design for avoiding the eight-job Windows
CI run when a change is documentation-only. Recording this policy does not
change the current workflow behavior.

## Decision

Use a stable, always-created workflow check with conditional heavy jobs rather
than workflow-level `paths-ignore`.

The workflow continues to start for `push`, `pull_request`, and manual
`workflow_dispatch` events. A lightweight first job classifies the changed
paths as either `docs-only` or `requires-ci`. The existing build, regression,
coverage, security-preflight, packaging, and package-smoke jobs run only for
`requires-ci`.

The workflow then always creates a final `CI status` job:

- for `docs-only`, it succeeds after recording that heavy CI was intentionally
  skipped;
- for `requires-ci`, it succeeds only when every existing heavy job succeeds;
- for classification failure, cancellation, or an unexpected skipped heavy
  job, it fails closed.

Branch protection should require only this stable `CI status` check. The
individual heavy jobs remain useful diagnostics, but must not be the sole
required checks because their intentional skip state varies by change class.

## Change classification

The classifier should use an explicit documentation allowlist, not a broad
source-path allowlist. A change is `docs-only` only when every changed path is
one of the approved documentation paths, for example:

```text
docs/**
*.md
**/*.md
```

Everything else is `requires-ci`, including source, tests, tools, fixtures,
generated artifacts, project/build metadata, workflow/action files, schema
pins, `LICENSE`, and release metadata. A mixed documentation/code change also
requires the complete CI flow.

The classifier must run in PowerShell and fail closed if the event diff cannot
be resolved. Manual `workflow_dispatch` runs must default to
`requires-ci` so that an operator can always force the complete validation
chain. If merge queues are introduced, `merge_group` must use the same
classification and stable status contract.

## Required workflow shape

The implementation should preserve the existing job graph and add the
classification dependency explicitly:

```yaml
jobs:
  changes:
    name: Classify changes
    # Emits docs_only=true|false and fails closed on an unknown diff.

  build:
    needs: changes
    if: needs.changes.outputs.docs_only != 'true'

  # The other heavy jobs use the same classification guard and retain their
  # current dependencies.

  ci-status:
    name: CI status
    if: ${{ always() }}
    needs:
      - changes
      - build
      - deterministic-generation
      - unit-runtime
      - regression
      - compatibility
      - coverage
      - release-preflight
      - package
```

`ci-status` must explicitly distinguish the intentional `docs-only` case
from a skipped or failed heavy job. It must not treat an unexpected skip as a
pass. The current `.github/workflows/p34-schema-update.yml` remains manual and
is not part of this routing change.

## Evidence and acceptance gates

Before enabling the policy, verify all of the following in a pull request and
on a branch push:

1. A change under `docs/**` creates `CI status`, runs no heavy Windows job, and
   is mergeable when the stable check passes.
2. A root Markdown-only change has the same result.
3. A documentation change plus one source, test, tool, fixture, workflow,
   schema, artifact, build, or license file runs all existing heavy jobs.
4. A workflow or action change always runs the complete CI flow.
5. A manual dispatch always runs the complete CI flow.
6. A classifier error, cancelled dependency, or unexpected skip fails the
   stable check rather than silently passing.
7. Branch protection requires the stable `CI status` check and does not leave
   a path-filtered workflow check permanently pending.

The implementation should add a focused PowerShell boundary test for the
classification matrix before changing branch protection. No Gallery,
Cloudflare account, mutation, or release action is implied by this policy.
