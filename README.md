# tech-calc

A native scientific calculator for macOS and iOS with the function set of a TI-84 Plus CE — driven either by the familiar keypad or by free-form typed expressions, with a result history you can actually read, select, and copy.

## Why

The hardware has the functions but a 16-character display, a history that vanishes as it scrolls, and no way to get an answer into a document. macOS Calculator and the web equivalents have the display but stop well short of the function set — no distributions, no inference tests, no regressions, no `rref`, no TVM solver. tech-calc is the TI-84's capability on a desktop-class screen with a keyboard.

The TI-84 is the reference for *what the calculator can do* and *how its keys are organised*. It is not the reference for how the app looks, and none of its trade dress is reproduced.

## Status

**Built.** The whole TI-84 function set is implemented and under headless test, results are typeset in the history pane, and the form screens — `STAT TESTS`, the TVM solver, the list and matrix editors, `MODE` — are in the app. What remains before a release is visual QA and packaging on macOS, not engine work.

| Phase | Scope | State |
| --- | --- | --- |
| M1 | Tokenizer, parser, evaluator, scalar function set, MODE, history, persistence | **Done** |
| M2 | Lists `L1`–`L6`, matrices `[A]`–`[J]`, their editors and operations | **Done** |
| M4 | `STAT CALC`, `DISTR`, `TESTS` — regressions, distributions, hypothesis tests, intervals | **Done** |
| M5 | TVM solver and finance functions, number bases, bitwise operations | **Done** |
| M6 | AST-to-LaTeX serializer, typeset result rendering, the form screens | **Done** |

Graphing, TI-BASIC, Python and CAS are explicit non-goals.

### The app

- **Typeset results.** Fractions are built up, radicals are stroked, exponents and subscripts are set at script size, and matrices are bracketed and column-aligned — drawn by a recursive SwiftUI view over the evaluator's own AST. There is no web view and no third-party typesetting library, and the geometry is computed in `TechCalcCore` as pure values, so a layout is asserted in a test rather than by looking at it.
- **Copy as LaTeX, export as Markdown.** A separate AST-to-LaTeX serializer serves the clipboard and the export; nothing on screen is drawn through LaTeX.
- **The form screens.** Seventeen `STAT TESTS` procedures share one screen, because a form is data: `StatForms` declares the fields each procedure collects and runs it. The TVM solver, the `L1`–`L6` list editor, the `[A]`–`[J]` matrix editor and `MODE` are the other four. No screen computes anything — each collects values and calls a pure function.

### The engine

- **One input path.** Keypad presses and typed characters land in the same edit buffer and are lexed by the same tokenizer, so `sin⁻¹(.5)` typed and `sin⁻¹(.5)` keyed are indistinguishable downstream.
- **TI precedence, exactly.** Implicit multiplication binds as `*` does and groups left to right, so `1/2X` is `(1/2)X`. Negation binds looser than exponentiation, so `-3^2` is `-9` and `(-3)^2` is `9`. `^` is right-associative, so `2^3^2` is `512`. Adjacent calls such as `sin(2)cos(2)` are a product. Unclosed parentheses close themselves on ENTER.
- **The `2nd` / `ALPHA` state machine**, including single-shot latches and A-LOCK.
- **Complex arithmetic**, always computed. `REAL` / `a+bi` / `re^θi` governs presentation and whether a complex answer is refused as `ERR:NONREAL ANS` — there is no separate real code path to drift out of step.
- **`MODE`:** DEG/RAD, NORMAL/SCI/ENG, FLOAT and fixed 0–9, the complex modes, and answer as auto/decimal/fraction. `▸Frac` reconstructs a rational up to denominator 9999.
- **`Ans`, `STO▸`, variables `A`–`Z` and `θ`**, and `STO▸rand` to reseed.
- **History** of up to 500 entry/result pairs, selectable, with tap-to-reinsert and `2ND ENTRY` recall.
- **Error parity.** Errors carry TI names — `ERR:SYNTAX`, `ERR:DOMAIN`, `ERR:DIVIDE BY 0`, `ERR:NONREAL ANS`, and the rest — because getting the *right* error is part of matching the calculator.

### The function set

- **Scalar:** trigonometry and hyperbolics with their inverses, logarithms and `logBASE(`, roots and powers, `MATH NUM` (`abs` `round` `iPart` `fPart` `int` `min` `max` `lcm` `gcd` `remainder`), `MATH PROB` (`nPr` `nCr` `!` `rand` `randInt(` `randNorm(` `randBin(` `randIntNoRep(`), `MATH CMPLX` (`conj` `real` `imag` `angle`), `ANGLE` (`°` `ʳ` `R▸Pr(` `R▸Pθ(` `P▸Rx(` `P▸Ry(`), `TEST`/`LOGIC`, and the iterative `fnInt(` `nDeriv(` `Σ(`.
- **Lists and matrices:** `L1`–`L6` and named lists, `[A]`–`[J]`, list literals and matrix literals, element-wise broadcasting, `SortA(` `SortD(` `dim(` `Fill(` `seq(` `cumSum(` `ΔList(` `augment(` `List▸matr(` `Matr▸list(`, the `LIST MATH` reductions, and `det(` `T` `identity(` `randM(` `ref(` `rref(` with the row operations. Indexing is 1-based, and the matrix work is pure Swift Gaussian elimination with an explicit singularity tolerance.
- **Statistics:** `1-Var Stats`, `2-Var Stats`, and eight regression families; the whole `DISTR` menu (normal, Student *t*, chi-square, *F*, binomial, Poisson, geometric) with their inverses; ten hypothesis tests including Welch degrees of freedom; and seven confidence intervals including `LinRegTInt`.
- **Finance:** the TVM equation solved for any of `N`, `I%`, `PV`, `PMT` and `FV`, with `P/Y`, `C/Y` and BEGIN/END timing; `npv(` `irr(` `bal(` `ΣPrn(` `ΣInt(` `▸Nom(` `▸Eff(` `dbd(`.
- **Number bases:** `0b` and `0h` entry, `▸Bin` `▸Hex` `▸Oct` `▸Dec` display, and `bitAnd(` `bitOr(` `bitXor(` `bitNot(` over a 32-bit two's-complement word. The bitwise functions are deliberately *separate* from the TI's boolean `and` / `or` / `xor` / `not`, which keep their 0/1 semantics unchanged.

## Install

Requires macOS 14 or later (iOS 17 for the iOS target, which compiles and launches but is not a ship target in v1).

```sh
git clone https://github.com/jsglazer/tech-calc.git
cd tech-calc
xcodegen generate
xcodebuild -project TechCalc.xcodeproj -scheme TechCalcMac -configuration Release build
```

## Architecture

```
Sources/TechCalcCore   pure domain logic — the headless test gate runs against this
Sources/TechCalcUI     shared SwiftUI, platform differences behind #if os(...)
Sources/TechCalcMac    macOS shell (the v1 ship target)
Sources/TechCalcIOS    iOS shell
Tests/TechCalcCoreTests
```

`TechCalcCore` imports nothing but `Foundation`. It has no SwiftUI, AppKit, UIKit or WebKit; no JavaScript engine; no Accelerate, vDSP, BLAS or LAPACK; and no external package dependencies at all. It reads no clock, opens no file and touches no user defaults — persistence crosses the boundary as an injected `StorageProvider`, and randomness as an injected seeded `RandomSource`, so a run is exactly reproducible.

A few load-bearing decisions:

- **A native Swift parser**, not JavaScriptCore or mathjs: iOS has no JIT, and a Pratt parser over the TI precedence table keeps the AST directly inspectable.
- **One `FunctionCatalog`** declares every supported function once — name, arity, argument labels, menu path, keypad token. The tokenizer, the parser, the menus and the keypad all read it, so a function's spelling exists in exactly one place.
- **One `TIValue`** crosses the evaluator, and complex arithmetic is unconditional.
- **`Double` throughout**, with parity achieved at the display layer: results round to 10 significant digits and the formatter honours the notation and decimal settings. The TI's 14-digit BCD representation is not reproduced.
- **Every iterative routine is step-limited** — Romberg integration caps at 20 refinement levels, summation at a million terms, the distribution inverses and the `I%` / `irr(` root-finds at 200 — and throws `ERR:ITERATIONS` rather than spinning.
- **One solver per job.** Every distribution inverse routes through a single bracketed bisection-with-Newton; `I%` and `irr(` share a single bisection-with-secant. There is one convergence policy to audit, not one per function.
- **No statistical or financial arithmetic in a view.** Every test, interval, regression and TVM solve is a pure function over an input struct; the form screens and the typed command form are two callers of it, and a mechanical test reads the SwiftUI sources to keep it that way.
- **Typeset geometry is computed in the core.** `TypesetLayout` turns an AST into positioned boxes — widths, ascents, baseline shifts — and the SwiftUI view only draws them. A layout that can only be checked by looking at it would be a layout that should have been a pure function first.
- **One versioned document.** `state.json` carries the mode, `A`–`Z`, `Ans`, the lists, the matrices, the history and the TVM solver's fields, written atomically through the injected provider and migrated on read. Solver *inputs* persist because they are a document the user fills in and comes back to; computed statistics results do not.
- **1-based indexing** at the TI syntax layer, with the conversion to Swift's 0-based indices confined to a single accessor per container type.

## Tests

```sh
swift test
```

303 tests across 28 suites, all headless, all deterministic: parser precedence and syntax, the keypad modifier state machine, scalar evaluation and error parity, display formatting, persistence roundtrips, seeded randomness, iterative numerics, 1-based indexing, list and matrix operations, the statistics and finance engines, number bases, a walk of the entire function catalog, the AST-to-LaTeX serializer as a pure string transform, the typeset layout's geometry, the stat-test forms against the procedures they call, the TVM solver form, and mechanical checks that the core's source contains none of the banned imports or unseeded randomness and that no statistical or financial logic has leaked into a SwiftUI view.

Inside that run is a 164-case TI-84 benchmark suite. **No expected value in it was produced by running tech-calc**: each entry carries a provenance naming R 4.5.3 (`stats::pnorm`, `stats::lm`, `stats::t.test`, `stats::uniroot`, …), the TI-84 Plus CE guidebook's documented rule evaluated in R, or a recorded developer decision — and the runner fails the build on a fixture that has no provenance or that names the code under test. The suite is regenerated by `~/.claude/scripts/techcalc-fixtures.R` rather than kept as a frozen blob.

## Licence

MIT — see [LICENSE](LICENSE).
