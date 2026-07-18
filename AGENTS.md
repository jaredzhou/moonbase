# MoonBase — Agent Guide

A [MoonBit](https://www.moonbitlang.com/) workspace monorepo with three modules: `jaredzhou/libs`, `jaredzhou/mooncedar`, and `jaredzhou/moonstore`. All target `native`.

## Workspace Overview

Defined in `moon.work`:

```
members = ["./libs", "./mooncedar", "./moonstore"]
```

Dependency graph:

```
moonbitlang/x@0.4.45
  ├── jaredzhou/libs         (url, jwt sub-packages)
  ├── jaredzhou/mooncedar    (ast, parser, evaluator sub-packages; independent)
  └── jaredzhou/moonstore    depends on jaredzhou/libs, jaredzhou/mooncedar, jaredzhou/pony (external)
```

When you change `libs`, `moonstore` must be rechecked because it imports `jaredzhou/libs`. `mooncedar` has no internal workspace dependencies.

## Workspace vs Module Commands

`moon publish` is **module-only** — you can't run it at the workspace root. Use `-C` or `cd`:

| Context | Commands |
|---------|----------|
| **Workspace root** | `moon check`, `moon test --all`, `moon fmt`, `moon info`, `moon clean --target all` |
| **Module directory** (via `-C` or `cd`) | `moon publish`, `moon build`, and all above commands scoped to one module |

## Common Commands

Run all commands from the repository root unless noted.

```bash
# Type-check the entire workspace
moon check

# Run ALL tests (blackbox _test + whitebox _wbtest) across all modules
moon test --all

# Run tests for a specific module
moon test --package jaredzhou/mooncedar

# Update snapshot tests (when behaviour changes intentionally)
moon test --update

# Format all source files
moon fmt

# Regenerate .mbti interface files (run before committing API changes)
moon info

# Download/fetch all external dependencies
moon update

# Check unused code / dead imports
moon check --unused

# Act on a specific module from the workspace root (with -C)
moon -C libs publish
moon -C pony publish
moon -C mooncedar publish
```

### Pre-commit

The `.githooks/pre-commit` hook runs `moon check`. Install it:

```bash
git config core.hooksPath .githooks
```

## Module Details

### `jaredzhou/libs` — Shared Libraries

**External deps:** `moonbitlang/x@0.4.45`

**Sub-packages:**

| Package | Purpose |
|---------|---------|
| `libs/url` | RFC 3986 URL parser |
| `libs/jwt` | JWT creation/validation (HS256, HS384, HS512) |

```bash
# Run libs tests only
moon test --package jaredzhou/libs
```

### `jaredzhou/mooncedar` — Cedar Policy Engine

**External deps:** `moonbitlang/x@0.4.45` (no workspace deps)

**Sub-packages (chained dependency):**

```
ast (no internal deps)
  └── parser (depends on ast)
  └── evaluator (depends on ast)
        └── root mooncedar (re-exports ast, parser, evaluator)
```

```bash
# Run mooncedar tests only
moon test --package jaredzhou/mooncedar

# Run a single test file
moon test --package jaredzhou/mooncedar --test authorizer_wbtest.mbt
```

Active development area. See `mooncedar/checkpoint.md` for the feature tracker (~8000 LOC, 546 tests).

**Development workflow for mooncedar:**

1. Make changes to `ast/`, `parser/`, `evaluator/`, or `authorizer.mbt`
2. Run `moon check --deny-warn` (catches type errors, fails on warnings)
3. Run `moon fmt` (ensure clean formatting — CI runs `moon fmt --check`)
4. Run `moon info` to regenerate `.mbti` interfaces (commit if changed)
5. Run `moon test --package jaredzhou/mooncedar` (verify all tests pass)
6. Update `mooncedar/checkpoint.md` to reflect new/changed items and updated test counts

### `jaredzhou/moonstore` — Object Storage Service

**External deps:** `jaredzhou/pony@0.2.4`, `jaredzhou/mooncedar@0.1.1`, `jaredzhou/libs@0.1.1`, `moonbitlang/async@0.19.4`, `moonbitlang/x@0.4.45`

An object storage service with a REST-ish HTTP API (S3-style buckets and objects). Features pluggable storage backends (in-memory, local filesystem) and metadata repos (in-memory, PostgreSQL). Authorization via `mooncedar` Cedar policies; HTTP API built on the [pony](https://github.com/jaredzhou/pony) web framework (external dep).

```bash
# Run moonstore tests only
moon test --package jaredzhou/moonstore
```

## Publishing Packages

MoonBit packages are published to [mooncakes.io](https://mooncakes.io). The package name comes from `moon.mod` (`name = "jaredzhou/..."`).

### Publish Order (required by dependency chain)

1. **`jaredzhou/libs`** — no workspace deps
2. **`jaredzhou/mooncedar`** — independent, can be published anytime
3. **`jaredzhou/moonstore`** — depends on `jaredzhou/libs`, `jaredzhou/mooncedar`

### Publish Steps

```bash
# 1. Bump version in moon.mod (e.g., 0.1.0 -> 0.1.1)
#    Edit each module's moon.mod:  version = "0.X.Y"

# 2. Verify everything is clean
moon check --deny-warn
moon fmt
moon info
moon test --all

# 4. Publish each module (moon publish is module-only, use -C from root)
moon -C libs publish
moon -C mooncedar publish
moon -C moonstore publish
```

### Post-Publish: Update Downstream Dependents

If you published a new version of `libs`, update `moonstore/moon.mod` to reference the new version:

```toml
import {
  "jaredzhou/libs@0.1.1",   # was 0.1.0
}
```

Then run `moon update` to refresh the lockfile.

## Updating Dependencies

```bash
# Fetch latest compatible versions of all deps
moon update

# Upgrade an external dependency (edit moon.mod first, then:)
moon update
```

## Project Conventions

- **Block syntax**: MoonBit code uses `///|` to separate blocks. Blocks can be processed independently during refactoring.
- **Deprecated code**: Move to a `deprecated.mbt` file in each sub-package directory.
- **Testing**: Prefer `inspect`-based snapshot tests (run `moon test --update` to refresh snapshots). Use `assert_eq!` for loop-based parametrized tests.
- **.mbti files**: Generated interface files. If `moon info` produces no .mbti diff, your change has no visible API impact — typically a safe refactoring.
- **Coverage**: Run `moon coverage analyze > uncovered.log` to find uncovered code.
- **Formatting**: Always run `moon fmt` before committing.
- **Sub-packages**: Each sub-package directory has its own `moon.pkg` (imports list) and its own test files.
