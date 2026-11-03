"""Refresh pinned public fixtures, or regenerate scenarios without the network.

No user data. Expected outputs are specified here using Python string operations,
independently of the MoonBit learner/interpreter. This is a project-defined
evaluation on public records, not an external benchmark or a customer trial.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures" / "public"


def fetch(url):
    request = Request(url, headers={"User-Agent": "ExampleLoom-public-data-evaluation"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def json_write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def acquire():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    manifest_path = FIXTURES / "manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for source in manifest["files"]:
            data = fetch(source["url"])
            if hashlib.sha256(data).hexdigest() != source["sha256"]:
                raise ValueError("Upstream snapshot differs: " + source["name"])
            (FIXTURES / source["name"]).write_bytes(data)
        return
    gitignore_sha = json.loads(fetch("https://api.github.com/repos/github/gitignore/commits/main"))["sha"]
    sources = [
        ("iana-zone1970.tab", "https://raw.githubusercontent.com/eggert/tz/2025b/zone1970.tab", "public-domain"),
        ("iana-LICENSE", "https://raw.githubusercontent.com/eggert/tz/2025b/LICENSE", "public-domain"),
        ("cldr-locales.json", "https://raw.githubusercontent.com/unicode-org/cldr-json/48.0.0/cldr-json/cldr-core/availableLocales.json", "Unicode-3.0"),
        ("cldr-LICENSE", "https://raw.githubusercontent.com/unicode-org/cldr-json/48.0.0/LICENSE", "Unicode-3.0"),
        ("gitignore-tree.json", f"https://api.github.com/repos/github/gitignore/git/trees/{gitignore_sha}?recursive=1", "CC0-1.0"),
        ("gitignore-LICENSE", f"https://raw.githubusercontent.com/github/gitignore/{gitignore_sha}/LICENSE", "CC0-1.0"),
    ]
    manifest = {"retrieved": "2026-11-03", "gitignore_commit": gitignore_sha, "files": []}
    for name, url, license_name in sources:
        data = fetch(url)
        (FIXTURES / name).write_bytes(data)
        manifest["files"].append({"name": name, "url": url, "license": license_name, "sha256": hashlib.sha256(data).hexdigest()})
    json_write(manifest_path, manifest)


def scenario(name, title, description, column, records, train, fields, source):
    folder = ROOT / "examples" / name
    folder.mkdir(parents=True, exist_ok=True)
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow([column])
    writer.writerows([r] for r in records)
    (folder / "input.csv").write_text(stream.getvalue(), encoding="utf-8", newline="\n")
    indices = [records.index(value) for value in train]
    result = {"title": title, "description": description, "file": "input.csv", "source": source, "data_kind": "public-records; project-defined transforms", "fields": []}
    for field, oracle in fields:
        expected = [oracle(record) for record in records]
        result["fields"].append({"name": field, "labels": [{"row": i, "output": expected[i]} for i in indices], "expected": expected})
    if name == "public-templates":
        result["fields"][1]["refinement_rounds"] = 2
        result["description"] += "模板名称存在多种解释：依次标注两条排名最高的分歧行，再选择规则。"
    json_write(folder / "scenario.json", result)
    print(json.dumps({"scenario": name, "rows": len(records), "training_rows": train, "fields": [f[0] for f in fields]}, ensure_ascii=False))


def generate():
    manifest = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
    for source in manifest["files"]:
        data = (FIXTURES / source["name"]).read_bytes()
        if hashlib.sha256(data).hexdigest() != source["sha256"]:
            raise ValueError("Fixture hash mismatch: " + source["name"])
    zones = sorted(line.split("\t")[2] for line in (FIXTURES / "iana-zone1970.tab").read_text(encoding="utf-8").splitlines() if line and not line.startswith("#"))
    locales = sorted(json.loads((FIXTURES / "cldr-locales.json").read_text(encoding="utf-8"))["availableLocales"]["full"])
    tree = json.loads((FIXTURES / "gitignore-tree.json").read_text(encoding="utf-8"))
    if tree.get("truncated"):
        raise ValueError("Git tree response is truncated")
    templates = sorted(item["path"] for item in tree["tree"] if item["type"] == "blob" and item["path"].endswith(".gitignore"))
    scenario("public-zones", "公开时区目录", "将 IANA 时区标识拆为区域和末级地点，用于设置页分组。", "zone", zones,
             ["Europe/London", "America/Argentina/Buenos_Aires", "Pacific/Port_Moresby"],
             [("area", lambda s: s.split("/")[0]), ("location", lambda s: s.split("/")[-1]), ("zone", lambda s: s)], "IANA tzdb 2025b / zone1970.tab")
    scenario("public-locales", "公开语言资源目录", "从 CLDR locale 标识生成语言分组和资源文件路径。", "locale", locales,
             ["en", "zh-Hans-HK", "fil"],
             [("language", lambda s: s.split("-")[0]), ("bundle", lambda s: "locales/" + s + ".json"), ("locale", lambda s: s)], "Unicode CLDR 48.0.0 / availableLocales.full")
    nested_template = next(s for s in templates if s.count("/") >= 2)
    scenario("public-templates", "公开模板目录", "从 github/gitignore 多级文件路径提取文件名与模板名称。", "path", templates,
             ["Ada.gitignore", "Global/VisualStudioCode.gitignore", nested_template],
             [("filename", lambda s: s.split("/")[-1]), ("template", lambda s: s.split("/")[-1][:-len(".gitignore")]), ("path", lambda s: s)], "github/gitignore @ " + manifest["gitignore_commit"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh", action="store_true", help="Download pinned public sources; otherwise work offline")
    args = parser.parse_args()
    if args.refresh:
        acquire()
    generate()
