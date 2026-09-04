# tech-calc

A native scientific calculator for macOS and iOS with the function set of a TI-84 Plus CE — driven either by the familiar keypad or by free-form typed expressions, with a result history you can actually read, select, and copy.

## Why

The hardware has the functions but a 16-character display, a history that vanishes as it scrolls, and no way to get an answer into a document. macOS Calculator and the web equivalents have the display but stop well short of the function set — no distributions, no inference tests, no regressions, no `rref`, no TVM solver. tech-calc is the TI-84's capability on a desktop-class screen with a keyboard.

The TI-84 is the reference for *what the calculator can do* and *how its keys are organised*. It is not the reference for how the app looks, and none of its trade dress is reproduced.

## Status

**Phase M1 of a phased build.** The expression engine is complete and under test; lists, matrices, statistics and finance land in later phases.

| Phase | Scope | State |
| --- | --- | --- |
| M1 | Tokenizer, parser, evaluator, scalar function set, MODE, history, persistence | **Done** |
| M2 | Lists `L1`–`L6`, matrices `[A]`–`[J]`, their editors and operations | Not started |
| M4 | `STAT CALC`, `DISTR`, `TESTS` — regressions, distributions, hypothesis tests, intervals | Not started |
| M5 | TVM solver and finance functions, number bases, bitwise operations | Not started |

Graphing, TI-BASIC, Python and CAS are explicit non-goals.

### Working today

- **One input path.** Keypad presses and typed characters land in the same edit buffer and are lexed by the same tokenizer, so `sin⁻¹(.5)` typed and `sin⁻¹(.5)` keyed are indistinguishable downstream.
- **TI precedence, exactly.** Implicit multiplication binds as `*` does and groups left to right, so `1/2X` is `(1/2)X`. Negation binds looser than exponentiation, so `-3^2` is `-9` and `(-3)^2` is `9`. `^` is right-associative, so `2^3^2` is `512`. Adjacent calls such as `sin(2)cos(2)` are a product. Unclosed parentheses close themselves on ENTER.
- **The `2nd` / `ALPHA` state machine**, including single-shot latches and A-LOCK.
- **Scalar function set:** trigonometry and hyperbolics with their inverses, logarithms and `logBASE(`, roots and powers, `MATH NUM` (`abs` `round` `iPart` `fPart` `int` `min` `max` `lcm` `gcd` `remainder`), `MATH PROB` (`nPr` `nCr` `!` `rand` `randInt(`), `MATH CMPLX` (`conj` `real` `imag` `angle`), `ANGLE` (`°` `ʳ` `R▸Pr(` `R▸Pθ(` `P▸Rx(` `P▸Ry(`), `TEST`/`LOGIC`, and the iterative `fnInt(` `nDeriv(` `Σ(`.
- **Complex arithmetic**, always computed. `REAL` / `a+bi` / `re^θi` governs presentation and whether a complex answer is refused as `ERR:NONREAL ANS` — there is no separate real code path to drift out of step.
- **`MODE`:** DEG/RAD, NORMAL/SCI/ENG, FLOAT and fixed 0–9, the complex modes, and answer as auto/decimal/fraction. `▸Frac` reconstructs a rational up to denominator 9999.
- **`Ans`, `STO▸`, variables `A`–`Z` and `θ`**, and `STO▸rand` to reseed.
- **History** of up to 500 entry/result pairs, selectable, with tap-to-reinsert and `2ND ENTRY` recall.
- **Error parity.** Errors carry TI names — `ERR:SYNTAX`, `ERR:DOMAIN`, `ERR:DIVIDE BY 0`, `ERR:NONREAL ANS`, and the rest — because getting the *right* error is part of matching the calculator.

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
- **Every iterative routine is step-limited** — Romberg integration caps at 20 refinement levels, summation at a million terms — and throws `ERR:ITERATIONS` rather than spinning.
- **1-based indexing** at the TI syntax layer, with the conversion to Swift's 0-based indices confined to a single accessor per container type.

## Tests

```sh
swift test
```

94 tests across 12 suites, all headless, all deterministic: parser precedence and syntax, the keypad modifier state machine, scalar evaluation and error parity, display formatting, persistence roundtrips, seeded randomness, iterative numerics, 1-based indexing, a walk of the entire function catalog, and mechanical checks that the core's source contains none of the banned imports or unseeded randomness.

## Licence

MIT — see [LICENSE](LICENSE).
