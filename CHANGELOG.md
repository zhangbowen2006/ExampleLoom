# Changes

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
