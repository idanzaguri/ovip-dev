# tools

Maintainer-only utilities. **Not** mirrored to the public `ovip` repo.

| File | Purpose |
|---|---|
| [`compile_check.py`](compile_check.py) | Builds every VIP, the combined all-VIP compile, every testbench, and the EDA Playground bundles. The fast "did I break anything?" check. Run with `python3 tools/compile_check.py`. |
| [`bundle_for_eda.py`](bundle_for_eda.py) | Chunks a VIP into ≤100 KB files for upload to EDA Playground. Run with `python3 tools/bundle_for_eda.py --vip apb --out eda_bundle/`. |
| [`sync_to_public.sh`](sync_to_public.sh) | Mirrors the publishable subset of this repo to the public `ovip` GitHub repo. The allowlist at the top of the script is the source of truth for what's "public". |
| [`WRAP_IMPLEMENTATION.md`](WRAP_IMPLEMENTATION.md) | Design notes for the deferred AXI WRAP burst implementation. Working document for whoever picks up that feature. |

## compile_check.py

Compile-only, so the default run takes about 15 seconds and is worth running
before every commit and before every `sync_to_public.sh`.

```bash
python3 tools/compile_check.py                    # vip + combined + tb + eda
python3 tools/compile_check.py --stages all       # also builds and runs examples/
python3 tools/compile_check.py --stages combined  # just the all-VIPs-at-once build
python3 tools/compile_check.py --vip apb --run    # one VIP, simulate its EDA bundle
```

| Stage | What it proves |
|---|---|
| `vip` | Each `verif/ovip_*/ovip_*.f` builds standalone -- the first thing an adopter does. Catches a filelist missing a dependency. |
| `combined` | All VIP filelists plus all testbench packages compile in **one** compilation unit and one library. Catches cross-VIP collisions (duplicate macros, types, classes, interfaces) that per-VIP builds hide. The `tb.sv` tops are left out, since every testbench names its top `tb`. |
| `tb` | Each `verif/ovip_*_testbench` builds the way `test_runner.py` builds it (same `lib/config.yaml`), `tb.sv` included. |
| `eda` | The EDA Playground bundle for each VIP is regenerated and compiled both ways the Playground might (single- and multi-file compilation unit), and the expected top module is checked to still be there. `--run` also simulates it. |
| `examples` | Every `examples/*/*/Makefile` compiles **and runs** clean. Opt-in (`--stages all`) because it simulates. |

Logs and libraries land under `sim/compile_check/` (gitignored); the exit code
is non-zero if any target failed. `--pedant` turns compile warnings into
failures, `--sim vcs|xcelium` switches simulator (best-effort -- Questa is the
exercised path), `-j` sets the number of parallel builds.

## bundle_for_eda.py

The VIP layout is discovered from the repo, so new source files are picked up
automatically and every VIP can be bundled:

```bash
python3 tools/bundle_for_eda.py --list
python3 tools/bundle_for_eda.py --vip axi --out eda_bundle/ --clean
python3 tools/bundle_for_eda.py --vip axi --test ovip_axi_b2b_test   # pick the active test
python3 tools/bundle_for_eda.py --vip ace --top example    # no testbench -> use an example
```

Output:

* `eda_tb.sv` -- paste into the Playground **testbench.sv** pane. Generated
  with the testbench's compile-time defines, the discovered test list (first
  one active, the rest commented out), and the Playground settings in its
  header comment.
* `eda_00_top.sv` + `eda_*_body_*.sv` -- upload via **Add file**.

Everything except `eda_tb.sv` is wrapped in an `` `ifdef OVIP_EDA_BUNDLE ``
guard, so the bundle compiles the same whether the Playground hands the
uploaded files to the compiler or only makes them available for `` `include ``.
As a side effect the bundle always presents exactly one top module, so no
simulator has to guess.

Validate a bundle locally before uploading it:

```bash
python3 tools/compile_check.py --stages eda --vip axi --run
```

The `eda` stage builds each bundle twice, because a compilation unit is the
scope a `` `define `` and any `$unit`-level declaration lives in, and tools
disagree on how to form it:

* **fcu** (single-file compilation unit) -- every file is its own unit, so
  macros do not leak between files. Questa's default.
* **mfcu** (multi-file compilation unit, `vlog -mfcu`) -- all files in one
  `vlog` invocation share a unit, so a macro from the first file is visible in
  the last.

We do not control which one EDA Playground uses, so the bundle is built to work
in both and `compile_check.py --stages eda` proves it before an upload.
