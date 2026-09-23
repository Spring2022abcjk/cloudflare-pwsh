# Reference Checkout and Cache Maintenance

## Status

**Deferred maintenance task.** This document records a future storage and
checkout improvement. It does not change the current `ref/` layout, schema
pin, generator behavior, or validation evidence.

The current project keeps ignored external research checkouts under each
worktree's `ref/` directory. This preserves the existing relative paths and
keeps the external evidence out of Git, but it duplicates large Git object
stores across worktrees. In the current checkout, `ref/api-schemas/.git` is
approximately 1 GiB; the complete local `ref/` tree is approximately 1.28 GiB.

## Problem and boundary

The following paths are external, ignored evidence rather than source files:

- `ref/api-schemas`
- `ref/cloudflare-typescript`
- `ref/cloudflare-python`
- `ref/cloudflare-go`

The schema checkout is an input to normalization, compatibility, coverage,
generation, package provenance, and schema-update validation. Its required
identity remains the pinned revision `28bfb054e5fa106464e9fbbf0ffbf362bc85234d`,
schema version `4.0.0`, and SHA-256
`f71c82b532b284e41a0e9de41ac1ee398e1b7b658f521e7f8ee478ce922fbf45`.
The research SDK checkouts remain separately pinned in [the documentation
index](./README.md#研究基线).

No shared mutable checkout may become an implicit source of truth. A schema
update or experimental revision must use an isolated temporary checkout and
must not modify the pinned reference used by another worktree.

## Preferred future design

Use one external cache of Git objects plus an isolated checkout at the
unchanged project-relative path in each worktree:

```text
E:\桌面\edit\cloudflare-pwsh-ref-cache\
├─ api-schemas.git\
├─ cloudflare-typescript.git\
├─ cloudflare-python.git\
├─ cloudflare-go.git\
└─ ref-lock.json

<project-worktree>\ref\api-schemas\
<project-worktree>\ref\cloudflare-typescript\
```

The preferred implementation is a shared bare mirror or object store with
separate linked Git worktree checkouts. This reduces duplicated `.git`
objects while preserving independent working trees and the existing
`ref/...` paths used by scripts and evidence.

For the research SDKs, provide checkouts only where the research task needs
them. They do not need to be copied into every historical project worktree.
The lock manifest must record repository URL, commit, source purpose, and
verification hash for each retained reference.

Do not replace the isolated checkouts with one shared writable directory or a
blind junction. A mutable shared directory permits one worktree's bootstrap or
experiment to change another worktree's input and would weaken provenance.

## Migration requirements

Perform this as a separate maintenance task after the current P3.5b work is
not in progress:

1. Inventory the existing reference commits, source versions, file hashes,
   worktree paths, and any local evidence that depends on them.
2. Create the external mirrors/cache without changing the pinned revisions.
3. Create independent `ref/...` checkouts at the recorded revisions with
   `core.autocrlf=false` and `core.eol=lf`.
4. Verify every retained worktree with
   `tools/Initialize-P34Schema.ps1 -VerifyOnly` and the schema SHA-256 gate.
5. Run the relevant P1–P3.4 regression, deterministic, coverage,
   compatibility, package provenance, and candidate-smoke checks.
6. Confirm that report `sourcePath` values remain `ref/api-schemas/...` and
   that no tracked files change solely because of the storage migration.
7. Only after the checks pass, remove duplicated ignored checkouts from old
   worktrees. Keep the ABC evidence directory
   `E:\桌面\edit\cloudflare-pwsh-abc-evidence-533fd52` intact.

## Acceptance and stop conditions

The migration is complete only when all retained worktrees resolve the same
pinned schema revision and SHA-256, isolated schema-update validation still
passes, candidate provenance still binds to the correct source revision, and
the project remains clean apart from explicitly ignored generated output.

Stop without deleting anything if the cache cannot be rebuilt from the
recorded commit, if a worktree's source path or hash differs, if a report
silently changes identity, or if a validation output is the only surviving
copy of historical release evidence.

Until this task is implemented and accepted, the existing per-worktree `ref/`
layout remains the authoritative local arrangement.
