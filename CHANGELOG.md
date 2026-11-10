# Changes

## 0.4.0 — 2026-11-10

- Add dynamic pivot grids, column combination, variable record segmentation and context propagation (21 structural operations).
- Rank programs by declared cost; use bounded best-first exploration, finite composition witnesses and bounded row-learning caches.
- Infer finite regex contexts/literal normalization, and accept training pairs with different output dimensions for disambiguation.
- Correct the external benchmark audit: retain 250 tasks, distinguish 25 missing-test-answer sentinels, and compare both engines on 225 available gold outputs.
- Preserve three paired old/new runs, gains and regressions; improve coverage without claiming overall speedup or mature-system parity.
- Add pandas differential validation, 78 core tests and new real-browser workflows.

## 0.3.0 — 2026-11-10

- Add short-circuit condition AST and bounded partition-based fallback induction, sharing search budgets and rejecting singleton memorization branches.
- Integrate MoonBit core regular expressions for matches, captures and replacement; expose capture hints in learning and validate repeat expansion limits.
- Add 17 structural table operators, version-2 pipelines with schema rebinding, and multi-example structural search with explicit state/evaluation/memory limits.
- Ship a standalone table workbench, unseen-table examples and CLI learn-table/pipeline/transform workflows; invalidate stale rules and block failed exports.
- Include all 250 upstream Foofah MIT-licensed tasks with pinned provenance; measure training consistency, held-out top1/any, failures and latency without using test answers for selection.
- Add core boundary tests, JavaScript regex differential checks and real browser flows; document exact learned-language limits and gaps versus PROSE/Foofah.

## 0.2.0 — 2026-11-03

- Learn punctuation and case/trim variants from all examples; canonicalize label order and duplicates.
- Accept explicit text separators; compose token extraction with fixed prefix/suffix removal.
- Cache transitions for shared output positions within a bounded search; expose reuse statistics.
- Invalidate selected rules and exports when labels change, including across output-field switches.
- Add three pinned public datasets (1,390 records), interactive ambiguity correction, full CSV export and SQLite integration.
- Expand core tests from 41 to 49 and browser regression to public workflows.
- Preserve the observed initial template-name failure and search limits in validation documentation.

## 0.1.0 — 2026-11-02

- Initial MoonBit learner/interpreter, portable recipes, CSV/JSONL, CLI and standalone workbench.
