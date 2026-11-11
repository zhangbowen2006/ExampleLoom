# JSON protocol, row recipe v1 and table pipeline v2

The exported `handle(request: String) -> String` always returns JSON. Ordinary input failures are `{ "ok": false, "error": "..." }`. There is no network, filesystem or host-code execution in this boundary.

## Atomic regex and repeated records (v0.10.0)

The extended `(?rx)` profile accepts `(?>...)` and possessive quantifiers such as `*+`, `++`, `?+`, and `{m,n}+`. An atomic group commits to its selected internal match and cannot later backtrack inside it. Atomic groups and lookarounds share the runtime nesting limit of eight and the execution budget; this remains a bounded subset rather than full PCRE. See [the profile and measured PCRE2 comparisons](REGEX_PROFILE.md).

`["preserve_extra_columns"]` is an optional v2 pipeline marker and may occur only once, as the first step. The pipeline binds the saved required columns by name, then appends previously undeclared input columns in their incoming order; missing required columns still fail. Without the marker, existing v2 pipelines retain their prior select-only behavior. Later explicit transforms such as `select` or `map_rows` may still drop fields. The [example](../examples/structures/preserve-columns.json) is a manually specified pipeline, not an inferred one.

`["pivot_records","key","value","name"]` converts a stream of key/value rows to a generic-column grid. Each row whose key equals the nonempty marker starts a new record; the first row must have that marker. Other duplicate keys in the same record and blank keys fail. The first output row contains keys in first-seen order across all records, followed by one row per record; absent keys become empty strings and later records may introduce new keys. Input columns other than the specified key and value are discarded. This convention is explicit: a repeated marker always starts a new record, not a duplicate-key error. Normal limits of 64 columns and 200,000 output cells apply. The learner can propose the operator from training examples, but one example can admit multiple explanations; review candidates and add examples. [Runnable example](../examples/structures/key-value-records.json) · [constructed record-level tests](../scripts/record-pivot-test.mjs).

## Bounded lookbehind and field-preserving updates (v0.9.0)

The extended `(?rx)` profile accepts fixed-width top-level lookbehind alternatives of different lengths, capture-free bounded variable-width branches up to 255 Unicode scalars, case-folded backreferences within a scoped `i` flag, and `\x{...}` scalar escapes. Repeated captures or captures within variable-width lookbehind branches are rejected; unbounded lookbehind is rejected. See [the exact profile](REGEX_PROFILE.md). This is not complete PCRE compatibility.

The additive v2 step `["update_columns", recipe]` replaces existing named columns while preserving other columns produced by earlier pipeline steps. `recipe.columns` binds only fields used by expressions; every output name must already exist. All expressions observe the original row, and any evaluation failure rejects the entire step. The outer v2 pipeline normally binds and selects its declared input columns; v0.10's explicit first-step `preserve_extra_columns` marker opts into retaining undeclared input columns. The learner may propose `update_columns` after variable-width structural steps, and every proposed pipeline is replayed against all training pairs.

The `context-metrics` and `labelled-contacts` examples learn four-step context/detail programs. Their filters intentionally discard rows outside the shown detail pattern; validate the source format and compare candidates before applying to other data. Inference from one example does not prove that a constant slice or separator generalizes.

## Extended regex (v0.8.0, additive profile)

Existing recipe v1 and pipeline v2 encodings remain valid. A pattern starting with `(?rx)` explicitly selects the [extended native MoonBit profile](REGEX_PROFILE.md); other patterns retain the core/lexmatch dialect. Use it in `matches`, `capture`, `replace`, and synthesis `patterns` without a new recipe version. Example: `"(?rx)(?<=ref=)(\\d+)(?=;)"`. Replacement templates additionally accept `${name}` for named groups and `${12}` for multi-digit group indices through 32, preserving `$0..$9` and `$$`. This profile adds bounded lookaround and case-sensitive backreferences, not unrestricted PCRE. Unsupported syntax and resource exhaustion return errors. No external regex engine executes user data.

## Stable row ordering (v0.7.0)

The additive v2 step is `["sort_rows",[["region","text","asc"],["amount","decimal","desc"]]]`. Each key is exactly `[column,kind,direction]`, with kind `text` or `decimal` and direction `asc` or `desc`. Supply 1–8 distinct, existing column names. Keys are evaluated left-to-right; full ties retain their original input ordinal even in descending order. JSON pipeline v2 and every existing operator encoding remain valid.

Text uses case-sensitive Unicode scalar lexical order with no trimming, normalization or locale collation. Decimal accepts `[+-]?[0-9]+(\.[0-9]+)?` in 1–256 ASCII characters. Comparison is exact for that text range and does not use binary floating point or scaled machine integers. Spelling and cell values are preserved; negative zero compares equal to zero. Blank numeric cells, exponents, NaN, infinities, whitespace and grouping separators fail with row/column context. No invalid-value placement or implicit rounding is performed. The spreadsheet-safe CSV policy still applies to negative or formula-like output cells.

`synthesize_table` can infer up to three keys and mixed directions from complete training permutations. It bounds its ordering exploration to 32 prefixes and two completions per structural state; hitting those limits is reported as truncation. Each completion consumes the existing shared evaluation budget and is replayed on all examples. An already ordered example alone supplies no evidence that an ordering operation was intended. Runtime supports eight explicit keys independently of this learning bound.

See [three complete scenarios](../scripts/sorting-test.mjs), [Python reference generation](../scripts/generate-sort-oracle.py), and [source implementation](../sorting.mbt). This operator can be composed with existing steps; `sorted-measurements` learns Unpivot followed by decimal sorting.

## Compare retained table programs (v0.6.1, additive operation)

```json
{"op":"compare_table_candidates","pipelines":[{"version":2,"columns":["x"],"steps":[]},{"version":2,"columns":["x"],"steps":[["pack_rows",2,false]]}],"table":{"columns":["x"],"rows":[["a"],["b"],["c"]]}}
```

The request contains 1–8 pipelines and one complete, unlabelled table. It has no target field. Unknown request fields are rejected. `groups` preserves candidate order and contains `{candidates:[zeroBasedIndices],prediction:{ok:true,table:...}}` or `{candidates:[...],prediction:{ok:false,error:...}}`. Equality includes every header, row position and cell; previews are not used for grouping.

`status` is `consistent` for one successful outcome group, `disagreement` for multiple groups with at least one successful program, and `all_failed` when no program succeeds. `successful_candidates` counts programs, not outcome groups. `first_difference` describes the first two groups: `{kind:"columns"}`, `{kind:"row_count"}`, `{kind:"cell",row_index:0,column_index:0}` or `{kind:"error"}`; a single group has `null`. Cell coordinates are zero-based data indices excluding the header.

Input and each successful output are limited to 2000 rows, 20000 cells and 250000 UTF-16 units including column names. Exceeding a comparison budget aborts the operation with `ok:false`; it is not counted as an execution failure of that program. The engine does not sample partial tables. Normal transformation limits are unchanged. Comparison does not learn, rerank, select, export CSV or establish correctness. Use a smaller complete batch if necessary.

Native API: `compare_table_candidates(Array[Pipeline], Table) -> TableComparison raise LoomError`. See [the refinement workflow](../scripts/table-comparison-test.mjs) and [candidate types](../pkg.generated.mbti).

## Parse

```json
{"op":"parse","format":"csv","text":"code\n订单-0012\n订单-0081\n"}
```

Success: `{ "ok": true, "table": { "columns": ["code"], "rows": [["订单-0012"],["订单-0081"]] } }`. Format can also be `jsonl`.

## Synthesize

```json
{"op":"synthesize","examples":[{"input":["订单-0012"],"output":"0012"},{"input":["订单-0081"],"output":"0081"}],"rows":[["订单-123456"]],"options":{"max_candidates":64}}
```

Success contains ordered `candidates` (expression, description, cost), `disagreements` (zero-based row_index, split score and outcome groups), `stats`, `status` and `truncated`. Options may override max_candidates, max_parts, max_atom_evaluations, max_steps and max_frontier within documented bounds. `exhausted_observed_grammar` refers only to the observed finite search grammar, never the universe of programs. Other statuses mark resource limits. Multiple limits may occur; the status is the most recently encountered reason and truncated remains true.

Optional top-level `separators: ["来自"]` adds up to 16 nonempty separators, each at most 16 Unicode scalar values. Punctuation separators are inferred from every example. Example sorting/deduplication makes label order deterministic. v0.2 stats add `cached_states` and `cache_hits`; `steps` counts path expansions and uncached atom advances, so it is not directly comparable to v0.1.

## Validate and apply

```json
{"op":"validate_recipe","recipe":{"version":1,"columns":["code"],"outputs":[{"name":"id","expression":["token",["field",0],"-",-1]}]}}
```

```json
{"op":"apply","recipe":{"version":1,"columns":["code"],"outputs":[{"name":"id","expression":["token",["field",0],"-",-1]}]},"table":{"columns":["code"],"rows":[["订单-0012"],["订单-123456"]]}}
```

Apply returns output column names, indexed `rows` (each with `ok` and `values` or `error`), failures count and CSV. CSV is null if any row fails. `spreadsheet_safe` defaults true. No partial CSV is silently emitted.

## Expression encoding

| Operator | Encoding |
| --- | --- |
| Column | `["field",0]` |
| Constant | `["literal"," / "]` |
| Trim/case | `["trim",expr]`, `["lower",expr]`, `["upper",expr]` |
| Token | `["token",expr,"-",-1]` |
| ASCII run | `["run",expr,"digits",0]` or `"letters"` |
| Character slice | `["slice",expr,["start",1],["end",0]]` |
| Calendar | `["date",expr,"YYYYMMDD","YYYY-MM-DD"]` |
| Concatenation | `["concat",[expr1,expr2]]` |

The interpreter supports nested expressions; the synthesizer searches the narrower grammar described in ARCHITECTURE.md. An expression accepted by the interpreter is not necessarily learnable. Import rejects unsupported versions, unknown recipe fields/operators, wrong arity, invalid positions and excess depth/nodes.

## v0.3 conditions and regex

Synthesize accepts `patterns:["ref=([[:digit:]]+)"]` (up to 16 MoonBit regex patterns) and `branch_depth:0..3` (default 2). Conditions are fallback induction after flat search has no solution; each partition requires at least two observations. Budgets are shared, and `bounded_branch_search` reports incomplete search. See ARCHITECTURE.md for the narrower learned language and resource limits.

| Expression / predicate | Encoding |
| --- | --- |
| Conditional expression | `["if",condition,yesExpr,noExpr]` |
| Regex capture | `["capture",expr,pattern,group,occurrence]` |
| Global regex replacement | `["replace",expr,pattern,"$2:$1:$$"]` |
| Equality predicate | `["equals",expr1,expr2]` |
| Empty string predicate | `["empty",expr]` |
| Regex predicate | `["matches",expr,pattern,fullMatchBoolean]` |
| Boolean predicates | `["not",condition]`, `["all",[conditions]]`, `["any",[conditions]]` |

If/All/Any short circuit. Capture occurrence may be negative (from the last non-overlapping match). Unprefixed regex uses MoonBit core/lexmatch; `(?rx)` selects the documented extended profile. The learner can synthesize certain capture-based replacements from hints; it does not infer arbitrary regex programs. Old recipes remain readable; older engine versions reject new operators.

## Table synthesis

```json
{"op":"synthesize_table","examples":[{"input":{"columns":["id","Jan","Feb"],"rows":[["A","1","2"]]},"output":{"columns":["id","month","value"],"rows":[["A","Jan","1"],["A","Feb","2"]]}}],"options":{"max_depth":4,"max_states":128,"max_evaluations":2000,"max_candidates":8}}
```

Success contains `candidates:[{"pipeline":...,"description":[steps]}]`, `status`, `truncated`, and `stats:{states,evaluations,rejected,row_searches}`. Empty candidates mean no solution within this grammar/budget, not impossibility. `examples` accepts 1–8 complete input/output table pairs with consistent input schemas (output schemas may differ in v0.4); synthesis limits are lower than execution limits. Optional `separators` overrides the finite structural separator list; `patterns` supplies row-mapping regex hints. No holdout or expected-test-output field exists in the learner.

```json
{"op":"transform","pipeline":{"version":2,"columns":["id","Jan","Feb"],"steps":[["unpivot",["id"],["Jan","Feb"],"month","value"]]},"table":{"columns":["Feb","id","Jan"],"rows":[["9","B","007"]]}}
```

Success contains `table` and `csv`; any failed step returns `ok:false`, with no partial output. `spreadsheet_safe` defaults true. `validate_pipeline` accepts the `pipeline` field and checks format and static parameter validity; data-dependent constraints need actual execution. Input names are rebound before running steps; extra incoming columns are ignored, missing saved names are errors.

| Table operator | Step encoding |
| --- | --- |
| Project/reorder/rename | `["select",[sourceNames],[outputNames]]` |
| Row predicate | `["filter",condition]` |
| Row expressions | `["map_rows",rowRecipeV1]` |
| Split a cell into columns | `["split_column",column,literalSeparator,[newNames]]` |
| Explode into rows | `["explode",column,literalSeparator]` |
| Wide to long | `["unpivot",[keys],[valueColumns],variableName,valueName]` |
| Wide values to long, no variable column | `["fold",[keys],[valueColumns],valueName]` |
| Raw first-row labels to long | `["melt",[keys],[valueColumns],variableName,valueName,skipEmptyBoolean]` |
| Long to wide | `["pivot",[keys],variableColumn,valueColumn,[declaredLevels]]` |
| Consecutive rows to records | `["pack_rows",blockSize,columnwiseBoolean]` |
| Group values into padded records | `["group_rows",[keys],[valueColumns]]` |
| Transpose data cells | `["transpose"]` |
| Header promotion/demotion | `["promote_headers"]`, `["demote_headers"]` |
| Fill empty cells from preceding rows | `["fill_down",[columns]]` |
| Stable first-row-per-key deduplication | `["deduplicate",[keys]]` |
| Drop leading rows | `["drop_rows",count]` |

All cells remain strings. Transpose/PackRows/GroupRows/DemoteHeaders produce generated `c0..` names. Pivot is a closed-schema reshape; it rejects duplicate key-level cells rather than aggregating. GroupRows preserves duplicate values and pads uneven groups with empty strings. PackRows rejects an incomplete trailing block. No SQL join, arbitrary aggregation or unrestricted script is implied.


## v0.4 extensions

`synthesize_table.candidates[]` adds a numeric `cost`, ordered by a declared simplicity prior. It is not confidence. The same input schemas are required across training pairs; output widths/names may differ for dynamic transforms. This can disambiguate a whole-table transpose from fixed-size record packing.

| Operator | Encoding |
| --- | --- |
| Dynamic pivot with labels in first data row | `["pivot_grid",[keys],variableColumn,valueColumn]` |
| Combine selected columns | `["combine_columns",[sourceNames],separator,newName]` |
| Variable-size records | `["segment_rows",predicate,startsRecordBoolean]` |
| Carry header context into detail rows | `["carry_context",headerPredicate,[contextColumns]]` |

`select` now permits repeated source names with distinct output names. Output names must remain unique. Dynamic pivot accepts blank data labels and produces a new schema from observed categories; closed-schema `pivot` retains its previous unknown-level error behavior. Neither operator implicitly aggregates duplicate cells.

Flat synthesis also tries shared literal regex contexts and a finite literal-separator normalization grammar. Arbitrary regex and replacement synthesis remain unsupported. Table macro witnesses charge the normal primitive/depth budgets and do not inspect testing tables or expected test answers.

## v0.5 group measures and example-driven row learning

The v2 pipeline adds a group operation. Each measure has its own output name.

```json
["aggregate",["region"],[["orders","count"],["net","sum","cents"],["low","min","cents"],["high","max","cents"]]]
```

Groups follow first occurrence of the complete key tuple. An empty key list groups the entire table. On empty input an unkeyed count is `"0"` and unkeyed numeric measures yield an empty cell. With keys there are zero groups. Counts include every row. Numeric inputs accept an optional sign and ASCII decimal digits. Blanks, fractions, malformed values and Int64 overflow (including intermediate sums) produce a step error. Numeric output uses canonical decimal strings. A failing transform returns an error for the entire table.

The learner uses one or more input/output pairs. At least one training pair must reduce the row count for automatic aggregation inference. Put the original key names first in the output schema, followed by up to eight measures. Distinct keys can occur anywhere in the input schema. Candidate measures must match all training pairs before the learner combines alternatives. Ambiguous combinations have a bounded search.

The table workbench supports up to eight pairs and optional regex hints. The CLI accepts `learn-table --pairs batches.json --out report.json`. The manifest is an array such as `[{"data":"a.csv","target":"a-out.csv"},{"data":"b.csv","target":"b-out.csv"}]`. File paths are relative to the manifest. Both the single-pair and multiple-pair forms support `--patterns` and `--separators` JSON files. `--depth` sets the structural search depth.

Row learning can emit a whole-cell capture replacement with reordered or repeated groups. Learned templates require at least two nonconstant capture references. Unmatched whole-cell substitutions preserve the input. A full-match predicate can explicitly check a format before selecting a branch. Predicates and replacements continue to use the MoonBit core regex dialect.

## v0.6 learned normalization and compositions

The existing expression and v2 pipeline formats continue to encode the learned programs. Token rewrites and optional suffixes use `replace` and `if`. Optional suffix completion tests for an existing suffix before appending it.

Default structural separators now include `=`. The JSON protocol and MoonBit library use the same default list. Passing an explicit list selects the caller's separators.

Table row mapping accepts a single training row. Packing and projection witnesses are checked across every input/output pair. Split/Fold plans preserve per-record keys. Key-value blocks can be split into two columns, propagated by context and pivoted to a labelled grid. Context keys must identify records consistently. Duplicate key-level cells fail during execution.

A small whole-field search runs before the full row grammar. Both share the configured step budget. Atom values are evaluated once and reused. Search truncation still indicates incomplete candidate coverage.
