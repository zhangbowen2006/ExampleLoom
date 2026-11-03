# JSON protocol and recipe v1

The exported `handle(request: String) -> String` always returns JSON. Ordinary input failures are `{ "ok": false, "error": "..." }`. There is no network, filesystem or host-code execution in this boundary.

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
