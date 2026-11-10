"""Check the learned IANA territory-count pipeline through CSV, the CLI and SQLite."""
import csv
import hashlib
import json
import sqlite3
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/territory-counts"


def write_csv(path, columns, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(columns)
        writer.writerows(rows)


def reference(rows):
    with sqlite3.connect(":memory:") as db:
        db.execute("create table zone(territory text, name text)")
        db.executemany("insert into zone values (?, ?)", rows)
        # Keep first-seen territory order, including order within one source cell.
        return db.execute("""
            select item.value, cast(count(*) as text)
            from zone, json_each('["' || replace(zone.territory, ',', '","') || '"]') as item
            group by item.value
            order by min(zone.rowid * 1000 + cast(item.key as integer))
        """).fetchall()


def cli(*args):
    subprocess.run(["node", str(ROOT / "bin/exampleloom.mjs"), *map(str, args)], cwd=OUT, check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = ROOT / "fixtures/public/iana-zone1970.tab"
    manifest = json.loads((source.parent / "manifest.json").read_bytes())
    record = next(f for f in manifest["files"] if f["name"] == source.name)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == record["sha256"]
    raw = [line.split("\t") for line in source.read_text(encoding="utf-8").splitlines() if line and not line.startswith("#")]
    rows = [(r[0], r[2]) for r in raw]
    pairs = []
    for i, batch in enumerate((rows[:12], rows[12:30])):
        data, target = f"batch-{i}.csv", f"target-{i}.csv"
        write_csv(OUT / data, ["territory", "zone"], batch)
        write_csv(OUT / target, ["territory", "count"], reference(batch))
        pairs.append({"data": data, "target": target})
    (OUT / "batches.json").write_text(json.dumps(pairs), encoding="utf-8")
    cli("learn-table", "--pairs", "batches.json", "--out", "report.json")
    cli("pipeline", "--report", "report.json", "--choose", "0", "--out", "pipeline.json")
    held = rows[30:]
    write_csv(OUT / "held.csv", ["territory", "zone"], held)
    cli("transform", "--data", "held.csv", "--pipeline", "pipeline.json", "--out", "counts.csv")
    with (OUT / "counts.csv").open(encoding="utf-8", newline="") as stream:
        actual = list(csv.reader(stream))
    expected = reference(held)
    assert actual == [["territory", "count"]] + [list(row) for row in expected]
    pipeline = json.loads((OUT / "pipeline.json").read_bytes())
    assert [s[0] for s in pipeline["steps"]] == ["explode", "aggregate"]
    report = {"source": record, "sqlite": sqlite3.sqlite_version, "training_rows": [12, 18],
              "heldout_zone_rows": len(held), "heldout_territories": len(expected),
              "territory_zone_memberships": sum(int(count) for _, count in expected),
              "pipeline": pipeline, "matches_all_cells_and_order": True}
    (OUT / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
