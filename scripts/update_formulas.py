#!/usr/bin/env python3
"""Update tap formulas from each app's latest GitHub release.

Reads apps.json at the tap root:

    { "<formula-name>": { "repo": "OWNER/REPO", "tag_prefix": "v" }, ... }

For each app:
  1. fetch the latest published release tag
  2. skip if Formula/<name>.rb already points at that tag (no download)
  3. otherwise download the source archive, compute its SHA256, and rewrite
     the url / sha256 lines of the formula

Exit code is always 0 unless something unexpected breaks, so a single app's
failure never blocks the others (failures are reported per app).
"""

import hashlib
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def fetch_json(url):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def sha256_of(url):
    h = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=120) as r:
        for chunk in iter(lambda: r.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def update_formula(name, cfg):
    formula = ROOT / "Formula" / f"{name}.rb"
    if not formula.exists():
        print(f"skip {name}: Formula/{name}.rb not found")
        return False
    repo = cfg["repo"]
    prefix = cfg.get("tag_prefix", "v")
    try:
        tag = fetch_json(f"https://api.github.com/repos/{repo}/releases/latest")["tag_name"]
    except Exception as e:  # noqa: BLE001
        print(f"skip {name}: no published release ({e})")
        return False
    if not tag.startswith(prefix):
        print(f"skip {name}: tag {tag!r} does not start with {prefix!r}")
        return False

    content = formula.read_text()
    tag_suffix = f"/archive/refs/tags/{tag}.tar.gz"
    if tag_suffix in content:
        print(f"ok {name}: already at {tag}")
        return False

    url = f"https://github.com/{repo}{tag_suffix}"
    sha = sha256_of(url)
    updated = re.sub(r'^(\s*url ").*(")$', lambda m: m.group(1) + url + m.group(2),
                     content, count=1, flags=re.M)
    updated = re.sub(r'^(\s*sha256 ").*(")$', lambda m: m.group(1) + sha + m.group(2),
                     updated, count=1, flags=re.M)
    if updated == content:
        print(f"WARN {name}: pattern not found, formula unchanged")
        return False
    formula.write_text(updated)
    print(f"updated {name} -> {tag} (sha256 {sha[:12]}...)")
    return True


def main():
    apps = json.loads((ROOT / "apps.json").read_text())
    results = [update_formula(name, cfg) for name, cfg in apps.items()]
    print(f"updated {sum(results)}/{len(results)} formula(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
