"""Find incompatible test labels for identical learner-visible training data."""
from collections import defaultdict
from hashlib import sha256
from pathlib import Path
import json
import os
import runpy

ROOT = Path(__file__).resolve().parents[1]


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def audit(tasks):
    training_groups = defaultdict(list)
    eligible = [task for task in tasks if "train" in task]
    for task in eligible:
        canonical = sorted(task["train"], key=encoded)
        training_groups[encoded(canonical)].append(task)
    conflicts = []
    conflicting_groups = 0
    for training, group in training_groups.items():
        outputs = defaultdict(lambda: defaultdict(list))
        for task in group:
            for example in task["holdout"]:
                outputs[encoded(example["input"])][encoded(example["output"])].append(task["name"])
        disagreements = {key: values for key, values in outputs.items() if len(values) > 1}
        if not disagreements:
            continue
        conflicting_groups += 1
        for key, alternatives in disagreements.items():
            conflicts.append({
                "training_sha256": sha256(training.encode()).hexdigest(),
                "test_input_sha256": sha256(key.encode()).hexdigest(),
                "alternatives": [
                    {"output_sha256": sha256(output.encode()).hexdigest(), "tasks": names}
                    for output, names in sorted(alternatives.items())
                ],
            })
    return {
        "eligible_files": len(eligible),
        "conflicting_training_groups": conflicting_groups,
        "conflicting_test_inputs": len(conflicts),
        "conservative_first_choice_upper_bound": len(eligible) - conflicting_groups,
        "conflicts": conflicts,
    }


def source_contradictions(tasks):
    adapter = runpy.run_path(str(ROOT / "scripts/import-sygus.py"))
    evidence = []
    for task in tasks:
        if task.get("excluded") != "conflicting constraints":
            continue
        source = ROOT / "artifacts/sygus-2017" / task["name"]
        raw = source.read_bytes()
        assert sha256(raw).hexdigest() == task["sha256"]
        nodes = adapter["forms"](raw.decode("utf-8-sig"))
        seen = {}
        number = 0
        for node in nodes:
            if node[0] != "constraint":
                continue
            number += 1
            equation = node[1]
            lhs, rhs = equation[1:]
            if not isinstance(lhs, list):
                lhs, rhs = rhs, lhs
            arguments = [adapter["literal"](item) for item in lhs[1:]]
            output = adapter["literal"](rhs)
            key = encoded(arguments)
            if key in seen and seen[key][1] != output:
                evidence.append({
                    "task": task["name"], "source_sha256": task["sha256"],
                    "input_sha256": sha256(key.encode()).hexdigest(),
                    "constraint_numbers": [seen[key][0], number],
                    "output_sha256": [sha256(encoded(seen[key][1]).encode()).hexdigest(),
                                      sha256(encoded(output).encode()).hexdigest()],
                })
                break
            seen[key] = (number, output)
    return evidence


def main():
    source = ROOT / os.environ.get("STRING_BENCHMARK_DATA", "artifacts/sygus-2017/tasks.json")
    dataset = json.loads(source.read_bytes())
    report = {
        "revision": dataset["revision"],
        "protocol": dataset.get("protocol", 1),
        "training_cap": dataset.get("training_cap", 6),
        "scope": "The learner receives examples and the same fixed options. File names and original SyGuS grammars are not inputs to synthesis in this evaluation.",
        "meaning": "Identical training calls produce the same ranked program. If an overlapping test input has conflicting reference outputs, those tasks cannot all pass the fixed-first-choice metric. Additional labelled examples or explicit intent can distinguish the requests. This restriction does not apply to reporting multiple candidates or interactive clarification.",
        **audit(dataset["tasks"]),
        "inconsistent_source_constraints": source_contradictions(dataset["tasks"]),
    }
    # Check the diagnostic independently with an incompatible pair and a pair
    # sharing the same target. No engine results affect this check.
    samples = [{"input": ["x"], "output": "x"}]
    pair = [
        {"name": "a", "train": samples, "holdout": [{"input": ["y"], "output": "A"}]},
        {"name": "b", "train": samples, "holdout": [{"input": ["y"], "output": "B"}]},
    ]
    assert audit(pair)["conservative_first_choice_upper_bound"] == 1
    pair[1]["holdout"][0]["output"] = "A"
    assert audit(pair)["conflicting_test_inputs"] == 0
    destination = ROOT / "artifacts/string-benchmark-audit.json"
    destination.write_bytes((json.dumps(report, indent=2) + "\n").encode())
    print(json.dumps({k: report[k] for k in ("eligible_files", "conflicting_training_groups",
                                          "conflicting_test_inputs", "conservative_first_choice_upper_bound")}))


if __name__ == "__main__":
    main()
