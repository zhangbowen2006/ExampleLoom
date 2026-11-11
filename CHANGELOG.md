# Changes

## 0.6.1 — 2026-11-11

- Compare retained table programs on an unlabelled complete batch through the MoonBit API and workbench. Group exact output tables and execution errors and locate the first schema, row-count or cell difference.
- Complete an explicit refinement workflow: copy the compared input, leave the target blank for the user, invalidate old candidates, relearn and replay on a third batch. Discard delayed results after edits.
- Bound comparison to eight programs and 2000 rows / 20000 cells / 250000 UTF-16 units per input or successful output. Refuse oversized batches without sampling partial records or calling a resource-limit failure program evidence.
- Add nine core regressions (108 total), API/browser refinement tests and two existing Foofah failure cases. Search operators, budgets, ranking and evaluation protocols are unchanged.

## 0.6.0 — 2026-11-11

- Learn single-token literal rewrites and guarded suffix completion from observed inputs and outputs. Whole-field search shares the caller's budget with the complete grammar.
- Compose packing with projection, splitting with folding, and key-value context propagation with pivoting. Allow row learning from one table row, with the existing ambiguity feedback.
- Share default separators between the MoonBit API and JSON protocol, including equal-sign records. Prefer key-based grouping over fixed-size packing.
- Audit identical training calls with incompatible test labels. Correct the string evaluation's training cap from 6 to the supported 32 and retain an explicitly labelled legacy evaluation. Preserve original contradictory source constraints as diagnostic evidence.
- Validate 99 core tests and complete browser demonstrations. Actual external scores, failures and measurement settings are in [the benchmark report](docs/BENCHMARKS.md).

## 0.5.1 — 2026-11-11

- Learn fixed token prefixes and suffixes, including initials with variable-length names and Unicode scalar boundaries.
- Offer basic selectors for every column before expensive derived selectors. Use a budgeted suffix-cost lower bound to guide the row search and rank incidental constant selectors above explicit literals.
- Reject stale pipeline saves and loads, clear old candidates on a repeated search, recover a failed Worker on the next operation, and disable file selection while an operation is running.
- Validate 90 core tests per backend, name-initial workflows, delayed-response browser regressions and pinned external comparisons. The string task score increases from 82/104 to 88/104; full results and search costs are in [the report](docs/BENCHMARKS.md).


## 0.5.0 — 2026-11-10

- Learn whole-cell capture rewrites with reordered and repeated references. Infer regex shape predicates for mixed formats and conditional row maps inside table pipelines.
- Add stable group counts, checked Int64 sums and extrema. Match candidate measures against all training batches before pruning combinations.
- Accept up to eight CSV training pairs in the workbench and CLI. Replay exported programs on new batches and verify a territory-count workflow on the public IANA zone database against SQLite.
- Add a pinned external SyGuS string-task evaluation with duplicate-aware scoring and rerun the complete Foofah workload against the immutable v0.4.0 engine. See the [benchmarks](docs/BENCHMARKS.md).

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
