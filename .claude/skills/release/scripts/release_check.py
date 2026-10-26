#!/usr/bin/env python3
"""Static pre-release checks for ovip-dev: what changed since the last public
sync, and whether the per-VIP changelogs and versions are ready for it.

Checks:
  - the working tree is clean and on main
  - the range since the public repo's last "Sync from ovip-dev @ <sha>" commit
  - per VIP: files changed under verif/<vip>/ in that range, the Unreleased
    block of its CHANGELOG, the current version heading, a suggested bump
    (an "Added" subhead means minor, otherwise patch)
  - config switches: members added to verif/<vip>/src/<vip>_agent_config.sv in
    the range that the CHANGELOG never names (the v0.4.0 near-miss)
  - new source files in the range that no package include or filelist pulls in
    (the break an adopter of the public repo hits first)
  - every submodule (bin/runners) points at a commit that exists on its
    remote, so a clone of the pushed ovip-dev can check it out

Usage:
    python3 .claude/skills/release/scripts/release_check.py [--since <sha>]

Exit code 1 when a check fails. Read-only: nothing is modified.
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
VERIF = REPO / "verif"
PUBLIC = "idanzaguri/ovip"
VIPS = ["ovip_common", "ovip_axi", "ovip_apb", "ovip_axi_stream", "ovip_ace"]

MEMBER_RE = re.compile(r"^\+\s*(?:rand\s+)?(?:bit|int|int unsigned|longint|shortint|byte|string|real|time)\s+(\w+)\s*(?:=[^;]*)?;")


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, check=False).stdout


def last_sync_sha():
    try:
        out = subprocess.run(["gh", "api", f"repos/{PUBLIC}/commits", "--jq", ".[0].commit.message"],
                             capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    m = re.search(r"Sync from ovip-dev @ ([0-9a-f]{4,})", out)
    return m.group(1) if m else None


def unreleased_block(changelog):
    text = changelog.read_text()
    m = re.search(r"^## \[Unreleased\]\s*\n(.*?)(?=^## \[|\Z)", text, re.S | re.M)
    return (m.group(1).strip() if m else ""), text


def current_version(text):
    m = re.search(r"^## \[(\d+\.\d+\.\d+)\]", text, re.M)
    return m.group(1) if m else "none"


def bump(version, kind):
    major, minor, patch = (int(x) for x in version.split("."))
    return f"{major}.{minor + 1}.0" if kind == "minor" else f"{major}.{minor}.{patch + 1}"


def main():
    since = None
    if "--since" in sys.argv:
        since = sys.argv[sys.argv.index("--since") + 1]
    problems = []

    status = git("status", "--porcelain").strip()
    branch = git("rev-parse", "--abbrev-ref", "HEAD").strip()
    head = git("rev-parse", "--short", "HEAD").strip()
    print(f"HEAD {head} on {branch}; working tree {'clean' if not status else 'DIRTY'}")
    if status:
        problems.append("working tree is not clean")
    if branch != "main":
        problems.append(f"on branch {branch}, not main")

    since = since or last_sync_sha()
    if not since:
        problems.append("could not read the last sync sha from the public repo (gh api); pass --since <sha>")
        print("\n".join(f"FAIL: {p}" for p in problems))
        return 1
    rng = f"{since}..HEAD"
    commits = git("log", "--oneline", rng).strip().splitlines()
    print(f"\nlast public sync: {since}; {len(commits)} commit(s) since:")
    for c in commits:
        print(f"  {c}")
    if not commits:
        print("nothing to release")

    print("\nper VIP:")
    for vip in VIPS:
        vdir = VERIF / vip
        changed = git("diff", "--name-only", rng, "--", str(vdir)).strip().splitlines()
        src_changed = [f for f in changed if not f.endswith(("CHANGELOG.md", "README.md", "CONTRIBUTING.md"))]
        block, text = unreleased_block(vdir / "CHANGELOG.md")
        version = current_version(text)
        subheads = re.findall(r"^### (.+)$", block, re.M)
        kind = "minor" if any(s.startswith("Added") for s in subheads) else ("patch" if block else None)
        suggest = f"-> {bump(version, kind)} ({kind})" if kind else "unchanged"
        print(f"  {vip:<16} {len(changed):>2} file(s) changed, {len(src_changed):>2} of them source;"
              f" Unreleased: {', '.join(subheads) or 'EMPTY'}; version {version} {suggest}")
        if src_changed and not block:
            problems.append(f"{vip}: source changed in {rng} but CHANGELOG Unreleased is empty: {', '.join(src_changed)}")

        cfg = vdir / "src" / f"{vip}_agent_config.sv"
        if cfg.is_file():
            diff = git("diff", rng, "--", str(cfg))
            for line in diff.splitlines():
                m = MEMBER_RE.match(line)
                if m and m.group(1) not in text:
                    problems.append(f"{vip}: new config member `{m.group(1)}` is not named in CHANGELOG.md")

        added = git("diff", "--name-only", "--diff-filter=A", rng, "--", str(vdir / "src")).strip().splitlines()
        for f in added:
            name = Path(f).name
            pulled = subprocess.run(["grep", "-rl", name, str(vdir)], capture_output=True, text=True).stdout.split()
            if not [p for p in pulled if p != str(REPO / f) and p.endswith((".sv", ".f"))]:
                problems.append(f"{vip}: new file {f} is not included by any package or filelist")

    for line in git("submodule", "status").splitlines():
        sha, path = line.split()[:2]
        sha = sha.lstrip("+-U")
        sub = REPO / path
        subprocess.run(["git", "-C", str(sub), "fetch", "-q", "origin"], capture_output=True, check=False)
        on_remote = subprocess.run(["git", "-C", str(sub), "branch", "-r", "--contains", sha],
                                   capture_output=True, text=True, check=False).stdout.strip()
        branches = [b.strip() for b in on_remote.splitlines() if '->' not in b]
        print(f"\nsubmodule {path} at {sha[:9]}: {'on ' + branches[0] if branches else 'NOT on its remote'}")
        if not on_remote:
            problems.append(f"submodule {path} points at {sha[:9]}, which is not on its remote; push it first")

    try:
        tags = subprocess.run(["gh", "api", f"repos/{PUBLIC}/tags", "--jq", ".[0].name"],
                              capture_output=True, text=True, check=True).stdout.strip()
        print(f"\npublic repo: latest tag {tags}")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("\npublic repo: could not list tags")

    print()
    if problems:
        print("\n".join(f"FAIL: {p}" for p in problems))
        return 1
    print("release_check: no problems found (compile_check and the regressions are separate steps)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
