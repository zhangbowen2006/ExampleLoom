"""Download the pinned 2017 PBE Strings track into an ignored benchmark cache."""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha1, sha256
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen
import json
import re
import time

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "artifacts" / "sygus-2017"
REV = "13c8deb68a873635879c9a69bc78caebd340f646"
TRACK = "comp/2017/PBE_Strings_Track"
REPO = "SyGuS-Org/benchmarks"
TOKEN = re.compile(r'\s+|;[^\n]*|"(?:[^"]|"")*"|[()]|[^\s();"]+')


def fetch(url):
    for attempt in range(3):
        try:
            with urlopen(url, timeout=45) as response:
                return response.read()
        except OSError:
            if attempt == 2:
                raise
            time.sleep(1 + attempt)


def forms(text):
    stack, result, end = [], [], 0
    for token in TOKEN.finditer(text):
        if token.start() != end:
            raise ValueError("unrecognized SMT token")
        value, end = token.group(), token.end()
        if value.isspace() or value.startswith(";"):
            continue
        if value == "(":
            stack.append([])
        elif value == ")":
            node = stack.pop()
            (stack[-1] if stack else result).append(node)
        else:
            stack[-1].append(value)
    if stack or end != len(text):
        raise ValueError("incomplete SMT form")
    return result


def literal(node):
    if not isinstance(node, str) or not node.startswith('"'):
        raise ValueError("requires non-string value or computed constraint")
    # The track uses SMT-LIB quoted strings. Do not silently change the
    # meaning of a historical solver-specific escape.
    if "\\" in node:
        raise ValueError("string escape outside adapter dialect")
    return node[1:-1].replace('""', '"')


def split_task(text):
    nodes = forms(text)
    specs = [n for n in nodes if n[0] == "synth-fun"]
    if len(specs) != 1:
        raise ValueError("requires multiple synthesized functions")
    _, name, params, result, *_ = specs[0]
    if result != "String" or any(p[1] != "String" for p in params):
        raise ValueError("requires non-string type")
    observations = {}
    for n in nodes:
        if n[0] != "constraint":
            continue
        eq = n[1]
        if len(eq) != 3 or eq[0] != "=":
            raise ValueError("requires relational constraint")
        lhs, rhs = eq[1:]
        if not isinstance(lhs, list):
            lhs, rhs = rhs, lhs
        if not isinstance(lhs, list) or lhs[0] != name or len(lhs) != len(params) + 1:
            raise ValueError("requires computed constraint")
        args, output = tuple(literal(x) for x in lhs[1:]), literal(rhs)
        if args in observations and observations[args] != output:
            raise ValueError("conflicting constraints")
        observations[args] = output
    if len(observations) < 3:
        raise ValueError("fewer than three distinct inputs")
    def order(args):
        return sha256(json.dumps(args, ensure_ascii=False, separators=(",", ":")).encode()).digest()
    ordered = [{"input": args, "output": observations[args]} for args in sorted(observations, key=order)]
    count = min(6, len(ordered) - 1, (2 * len(ordered) + 2) // 3)
    return {"train": ordered[:count], "holdout": ordered[count:]}


def import_task(entry):
    name = entry["name"]
    path = CACHE / name
    raw = path.read_bytes() if path.is_file() else fetch(
        f"https://raw.githubusercontent.com/{REPO}/{REV}/{TRACK}/{quote(name)}")
    blob = sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()
    if blob != entry["sha"]:
        raise ValueError(f"{name}: Git blob hash mismatch")
    path.write_bytes(raw)
    task = {"name": name, "sha256": sha256(raw).hexdigest()}
    try:
        task.update(split_task(raw.decode("utf-8-sig")))
    except ValueError as exc:
        task["excluded"] = str(exc)
    return task


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    url = f"https://api.github.com/repos/{REPO}/contents/{TRACK}?ref={REV}"
    index_path = CACHE / "index.json"
    index = json.loads(index_path.read_bytes() if index_path.exists() else fetch(url))
    files = sorted((e for e in index if e["name"].endswith(".sl")), key=lambda e: e["name"])
    if len(files) != 108:
        raise ValueError("expected the complete pinned 108-file track")
    inventory = "".join(e["name"] + " " + e["sha"] + "\n" for e in files)
    if sha256(inventory.encode()).hexdigest() != "1d392a7ecde98a707476ddefcc1616692d5ea92a31db7d9cac5f61db9e32b367":
        raise ValueError("track inventory differs from the pinned Git tree")
    index_path.write_text(json.dumps(index), encoding="utf-8")
    with ThreadPoolExecutor(max_workers=6) as pool:
        tasks = list(pool.map(import_task, files))
    (CACHE / "tasks.json").write_text(json.dumps({"revision": REV, "tasks": tasks}), encoding="utf-8")
    print(f"Imported {len(tasks)} files, {sum('train' in t for t in tasks)} eligible")


if __name__ == "__main__":
    main()
