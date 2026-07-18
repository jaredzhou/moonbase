# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

Run these steps in order before committing (mirrors CI):

1. **`moon check --deny-warn`** — type-check and lint; fail on warnings.
2. **`moon fmt`** — format all source files. CI runs `moon fmt --check`; ensure
   no diff locally first.
3. **`moon info`** — regenerate `.mbti` interface files. CI runs
   `git diff --exit-code` after `moon info`; if `.mbti` files changed, commit
   them. If nothing changed, your change has no visible API impact (typically a
   safe refactoring).
4. **`moon test`** — run all tests. When snapshot outputs change intentionally,
   run `moon test --update` to refresh them and commit the updated snapshots.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.
