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
| `eda` | The EDA Playground bundle for each VIP, plus the all-VIP bundle, is regenerated and compiled both ways the Playground might (single- and multi-file compilation unit), and the expected top module is checked to still be there. `--run` also simulates each one. |
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
python3 tools/bundle_for_eda.py --vip all --out eda_all/   # every VIP in one bundle
```

`--vip all` is the cross-simulator check. It puts every VIP into a single
bundle behind a generated top that instantiates each VIP's interface, waits out
a reset and finishes; no test runs and no testbench defines are applied, so
what it proves is that the family builds and elaborates in its out-of-the-box
configuration. Upload it once and run it under each simulator EDA Playground
offers to cover the tools we have no licence for locally.

Output:

* `eda_tb.sv` -- paste into the Playground **testbench.sv** pane. Generated
  with the testbench's compile-time defines, the discovered test list (first
  one active, the rest commented out), and the Playground settings in its
  header comment.
* `eda_00_top.sv` + `eda_*_body_*.sv` -- upload via **Add file**.

### What the Playground actually compiles

Its run command is `<sim> ... uvm_macros.svh design.sv testbench.sv`: **only
the two panes are compiled**, and uploaded files exist purely to be
`` `include ``d. So `eda_tb.sv` goes in the testbench pane, design.sv stays
empty, and the uploads must keep their exact filenames.

`eda_00_top.sv` therefore carries a plain include guard and is self-sufficient.
Pasting it into a pane instead of `eda_tb.sv` still produces the design and one
top module. It must never be guarded on a macro only `eda_tb.sv` defines: that
turns a mis-paste into a file that compiles to nothing, and the only symptom is
the simulator later saying "no top-level unit found", which points nowhere.
Body chunks keep their per-package `` `ifdef ..._BODY `` guard, since a chunk
outside its package cannot compile at all.

### Validating a bundle before uploading

```bash
python3 tools/compile_check.py --stages eda --vip axi --run
```

The `eda` stage builds every bundle three times, once per way the files can
reach a compiler. All three must yield exactly one top module:

| Variant | Files compiled | Models |
|---|---|---|
| `site` | `eda_tb.sv` | the real Playground flow; `--run` simulates this one |
| `alone` | `eda_00_top.sv` | someone pasted the wrong file into the pane |
| `panes` | `eda_00_top.sv` + `eda_tb.sv`, one compilation unit | someone filled in both panes |

A compilation unit is the scope a `` `define `` and any `$unit`-level
declaration lives in, and tools form it differently: Questa gives each file its
own unit by default, `vlog -mfcu` merges them, and Xcelium merges by default.
The `panes` variant uses `-mfcu` for that reason.
