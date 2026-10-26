---
name: release
description: Cut an OVIP release end to end from ovip-dev. Checks that the changelogs, versions and config documentation are updated for everything since the last public sync, runs the compile check and the full regressions on Questa and Verilator locally and on VCS and Xcelium through EDA Playground (driven through Claude in Chrome), then pushes main, syncs the public ovip repo, tags it and publishes the GitHub Release. Use this whenever the user says release, cut a version, sync to the public repo, tag, publish, "is everything updated for a release", or wants the VIPs checked on all simulators before publishing, even if they only name one of those steps.
---

# OVIP release

A release here has two levels (see `tools/sync_to_public.sh` and the
per-VIP `CHANGELOG.md` files): each VIP under `verif/` carries its own semver
in its changelog, and the public repo `idanzaguri/ovip` gets one `vX.Y.Z` tag
plus a GitHub Release that collects the per-VIP versions. `ovip-dev` carries no
tags. Adopters take one VIP, so the per-VIP changelog is what they read; the
repo tag is the citable marker.

The stages below are in order because each one is the gate for the next: a
release with a stale changelog, or one that fails on a simulator the public
README promises, is worse than no release. Stop at the first real failure,
report it, and let the user decide. Three actions change something outside
this checkout: the changelog commit, the push plus sync, and the tag plus
GitHub Release. Each of them needs the user's explicit go-ahead in the turn it
happens, even though the user asked for the release as a whole.

## Stage 0: scope and update checks

```sh
python3 .claude/skills/release/scripts/release_check.py
```

It prints the commit range since the public repo's last `Sync from ovip-dev @
<sha>` commit, and per VIP: the files changed, the `Unreleased` subheads, the
current version and a suggested bump. It fails on a dirty tree, a VIP with
source changes but an empty `Unreleased` block, a config member added to
`*_agent_config.sv` that the changelog never names (that one nearly shipped
four undocumented switches in v0.4.0), and a new source file that no package
or filelist pulls in.

Then read every non-empty `Unreleased` block yourself and check it against the
diff of the range: an entry per user-visible change, base-class changes and
other breaks called out, the README section for every new switch, `.f` header
comments still true. Fix what is missing in a `docs:` commit (after a
go-ahead).

```sh
python3 tools/compile_check.py --stages all --run
```

All stages must pass. The `vip` stage is each public filelist on its own, the
first thing an adopter builds.

Versions: propose a bump per VIP from its `Unreleased` content (an `Added`
subhead is a minor, fixes and changes only a patch, untouched VIPs stay) and
one repo tag, then ask the user to confirm the numbers. Cut the changelogs in
one `docs:` commit, like `5ca33fb` ("docs: cut ovip_axi 0.4.0, ovip_common
0.4.0, ..."): move each `Unreleased` block under `## [X.Y.Z] -- YYYY-MM-DD`,
leave an empty `## [Unreleased]` on top, and explain the bump choices in the
commit body. No attribution trailers.

## Stage 1: local regressions, Questa and Verilator

```sh
for tb in ovip_apb_testbench ovip_axi_stream_testbench ovip_axi_testbench; do
  python3 bin/runners/regr_runner.py --tests verif/$tb/lib/regr.yaml --name rel_questa_$tb
  python3 bin/runners/regr_runner.py --tests verif/$tb/lib/regr.yaml --simulator verilator --name rel_vlt_$tb
done
```

Run them in the background and read `sim/regression/<name>/summary.txt`; pass
is `Failed: 0`. Expected: Questa 7/7, 6/6, 52/52; Verilator 7/7, 6/6, 51/52.
The one Verilator failure is `ovip_axi_xz_test`: Verilator is 2-state, and
its X-injection signals are deliberately not in
`verif/ovip_axi_testbench/lib/verilator.vlt`, so `uvm_hdl_force` reports
"unable to locate hdl path". Anything else is a real failure. A single
Questa failure that passes alone with the same seed is the known `$finish`
hang flake; re-run it before calling it a bug.

Verilator needs `/opt/verilator/current` first on PATH and `VERILATOR_SOLVER`;
`bin/setenv.local.sh` sets both and the runner sources it.

## Stage 2: VCS and Xcelium on EDA Playground

Follow `references/eda-playground.md`. In short: generate the five bundles
(`all`, `apb`, `axi`, `axi_stream`, `ace`) with `tools/bundle_for_eda.py`,
start `scripts/eda_server.py`, have the user log in to edaplayground.com in
Chrome, inject `scripts/eda_runner.js`, and run every bundle on both
simulators. The runner posts every log to the server; finish with

```sh
python3 .claude/skills/release/scripts/eda_summary.py --warnings
```

Known noise is listed in the reference (VCS `TLRCE`, Xcelium `PRPASZ`,
`ovip_mem_test` at the runtime cap). A compile error, a UVM_ERROR or
UVM_FATAL, or a warning not on that list stops the release.

The whole Playground pass takes about an hour, most of it the 53 AXI tests.
Report progress in one line now and then; the user cannot see the browser
work.

## Stage 3: the results table

Before anything leaves the machine, write the table the release notes and the
memory need:

| Suite | Questa | Verilator | VCS | Xcelium |
|---|---|---|---|---|
| all-VIP build | compile_check | - | 1/1 | 1/1 |
| ovip_apb_testbench | 7/7 | 7/7 | 7/7 | 7/7 |
| ovip_axi_stream_testbench | 6/6 | 6/6 | 6/6 | 6/6 |
| ovip_axi_testbench | 52/52 | 51/52 (xz) | 52/53 (mem cap) | 52/53 (mem cap) |
| ovip_ace example | compile_check | - | 1/1 | 1/1 |

Name every deviation from the expected numbers and whether it is a known one.

## Stage 4: push, sync, tag, publish

Each command after its own go-ahead; show the dry run first.

```sh
git push origin main
export OVIP_PUBLIC_REPO=git@github.com:idanzaguri/ovip.git
tools/sync_to_public.sh            # dry run: the staged file list and the co-author credits
tools/sync_to_public.sh --push     # one "Sync from ovip-dev @ <sha>" commit on public main
gh release create vX.Y.Z --repo idanzaguri/ovip --target main \
    --title "vX.Y.Z -- <one-line headline>" --notes-file <notes.md>
```

`gh release create` makes the tag on public `main`, which is the sync commit
just pushed, so no separate tag step. Write the notes file first (in the
scratchpad, not the repo) in the shape of the v0.4.0 release: a paragraph on
what the release is, the line "Per-VIP release history lives in each VIP's
`CHANGELOG.md`; this tag collects `ovip_common` A.B.C, `ovip_axi` ...", an
"Upgrade notes" section if any entry changes behaviour an existing testbench
sees, then one `## <vip> <version>` section per bumped VIP with its changelog
entries rewritten as prose, and a line on which simulators the release was
run on. The repo tag and the per-VIP versions are independent numbers and
will not line up; do not force them.

After publishing, `gh release view vX.Y.Z --repo idanzaguri/ovip` to confirm,
and update the memory notes on the cross-simulator status and the release
process with the new versions and date.

## Style

No em dashes anywhere, including commit messages and release notes (the
repo's docs use `--`). Commit messages and notes name things by their exact
identifiers from the code. No `Co-Authored-By` or other AI attribution
trailers on this repository.
