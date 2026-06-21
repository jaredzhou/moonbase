# MoonCedar — Agent Guide

A [MoonBit](https://docs.moonbitlang.com) project implementing the [Cedar](https://www.cedarpolicy.com) policy engine.

## Project Structure

- Each sub-package directory (`ast/`, `parser/`, `evaluator/`) has a `moon.pkg` file listing its dependencies. Each package has blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in `_wbtest.mbt`).

- The module root has `moon.mod` with module metadata and external dependencies.

- Dependency chain: `ast` (no internal deps) → `parser` (depends on `ast`), `evaluator` (depends on `ast`) → root `mooncedar` (re-exports all three).

## Coding Style

- Prefer MoonBit idiomatic patterns: use `for match` style over `while`/`loop` for `ArrayView`/`StringView` iteration.
- Keep parser code functional with `continue`/`break` in `for` expressions, avoiding imperative mutable accumulator loops.
- Follow the existing project conventions: `@ast.` prefix for cross-package imports, `pub(all)` for public API, record update `{ ..self, field: value }` for builder methods.
- Use `guard ... else { raise ... }` for early-exit validation instead of nested `if`/`match`.
- MoonBit code is organized in block style separated by `///|`. Block order is irrelevant; process block by block independently during refactoring.
- Keep deprecated blocks in a `deprecated.mbt` file in each directory.

## Tooling

- `moon check` — type-check / lint.
- `moon test` — run all tests. With `--update` to update snapshot tests when behaviour changes intentionally.
- `moon info` — regenerate `.mbti` interface files. If `.mbti` has no diff, the change has no visible API impact (typically a safe refactoring).
- `moon fmt` — format all source files.
- `moon coverage analyze > uncovered.log` — find code not covered by tests.

**After completing work, always run:**
```bash
moon info && moon fmt
```

Check `.mbti` diffs to verify API changes are expected.

**Testing conventions:**
- Prefer `inspect`-based snapshot tests. Run `moon test --update` to generate expected output, then verify with `moon test`.
- Use `assert_eq!` in loops where each snapshot may vary.

## Checkpoint Maintenance

After completing a new feature, bug fix, or significant refactor, update `checkpoint.md`:

- New/modified files in the project structure section
- Updated test counts and pass/fail status
- Any newly completed or newly pending items
- Keep the "待实现" (TODO) section current
