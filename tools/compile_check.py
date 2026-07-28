#!/usr/bin/env python3
"""Compile every OVIP VIP -- separately, together, and as an EDA Playground bundle.

This is the "did I break anything?" check. It never runs a regression; it only
builds, so it finishes in seconds and can be run after any edit.

Stages (pick with --stages, default: all except 'examples'):

  vip       Each VIP's public filelist (verif/ovip_*/ovip_*.f) on its own, in
            its own library. Catches a filelist that forgot a dependency --
            the exact failure an adopter hits first.
  combined  Every VIP filelist plus every testbench package in ONE compilation
            unit and ONE library. Catches cross-VIP collisions (duplicate
            macro, type, class or interface names) that per-VIP builds hide.
            The tb.sv tops are excluded: they are all named 'tb'.
  tb        Each verif/ovip_*_testbench block, compiled the way the test runner
            compiles it (verif/<block>/lib/config.yaml), tb.sv included.
  eda       Generate the EDA Playground bundle for each VIP with
            tools/bundle_for_eda.py and compile it both ways the Playground
            might (single- and multi-file compilation unit).
  examples  Build AND run every examples/*/*/Makefile. Slower -- opt in with
            --stages all or --stages examples.

Usage:
    python3 tools/compile_check.py                 # the usual pre-commit check
    python3 tools/compile_check.py --stages all
    python3 tools/compile_check.py --stages vip,combined --vip apb
    python3 tools/compile_check.py --pedant         # warnings count as failures

Simulators: questa/modelsim (default) is the fully exercised path. vcs and
xcelium are supported for the filelist-driven stages on a best-effort basis --
the filelists and example Makefiles already document those flows.
"""

import argparse
import contextlib
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO       = Path(__file__).resolve().parent.parent
VERIF      = REPO / "verif"
EXAMPLES   = REPO / "examples"
BUNDLER    = REPO / "tools" / "bundle_for_eda.py"
DEFAULT_OUT = REPO / "sim" / "compile_check"

sys.path.insert(0, str(REPO / "tools"))
from bundle_for_eda import discover_vips                    # noqa: E402

ALL_STAGES     = ["vip", "combined", "tb", "eda", "examples"]
DEFAULT_STAGES = ["vip", "combined", "tb", "eda"]

# Log patterns, per simulator. Compile-time only -- the run-time patterns are
# shared, since every UVM-1.2 simulator prints the same report summary.
COMP_FAIL = {
    "questa":  [r"^\*\* Error", r"^\*\* Fatal"],
    "vcs":     [r"^Error-\[", r"^\s*Error:"],
    "xcelium": [r"^\*E,", r"^ncvlog: \*E"],
}
COMP_WARN = {
    "questa":  [r"^\*\* Warning"],
    "vcs":     [r"^Warning-\["],
    "xcelium": [r"^\*W,"],
}
COMP_WAIVE = {
    "questa":  [r"\(vlog-2286\)", r"\(vopt-10587\)"],
    "vcs":     [],
    "xcelium": [],
}
RUN_FAIL = [r"UVM_ERROR.* @", r"UVM_FATAL.*@", r"^# \*\* Error", r"\$fatal"]

GREEN, RED, YELLOW, GREY, RESET = "\033[92m", "\033[91m", "\033[93m", "\033[90m", "\033[0m"


class Result:
    def __init__(self, stage, name, status, seconds, log, note=""):
        self.stage, self.name, self.status = stage, name, status
        self.seconds, self.log, self.note = seconds, log, note

    @property
    def ok(self):
        return self.status in ("PASS", "SKIP")


def scan_log(path, fail_pats, warn_pats, waive_pats):
    """(n_errors, n_warnings, first_error_line) for a compile/run log."""
    if not Path(path).is_file():
        return 1, 0, "(no log produced)"
    errors, warnings, first = 0, 0, ""
    fail = [re.compile(p) for p in fail_pats]
    warn = [re.compile(p) for p in warn_pats]
    waive = [re.compile(p) for p in waive_pats]
    for line in Path(path).read_text(errors="replace").splitlines():
        if any(w.search(line) for w in waive):
            continue
        if any(f.search(line) for f in fail):
            errors += 1
            first = first or line.strip()
        elif any(w.search(line) for w in warn):
            warnings += 1
    return errors, warnings, first


def run(cmd, cwd, log_path, env=None):
    """Run a command, tee-ing stdout+stderr into log_path. Returns returncode."""
    with open(log_path, "w") as log:
        proc = subprocess.run(cmd, cwd=str(cwd), stdout=log, stderr=subprocess.STDOUT,
                              env=env, text=True)
    return proc.returncode


# ----------------------------------------------------------------------
# Simulator front-ends (compile only)
# ----------------------------------------------------------------------
def compile_cmds(sim, filelist, mfcu=True):
    """(setup_cmd or None, compile_cmd) for a filelist-driven compile."""
    if sim in ("questa", "modelsim"):
        setup = ["vlib", "-type", "flat", "work"]
        cmd = ["vlog", "-sv", "-work", "work", "-l", "comp.log"]
        if mfcu:
            cmd.append("-mfcu")
        cmd += ["-f", str(filelist)]
        return setup, cmd
    if sim == "vcs":
        cmd = ["vcs", "-full64", "-sverilog", "-ntb_opts", "uvm-1.2",
               "-timescale=1ns/1ps", "-l", "comp.log", "-f", str(filelist)]
        return None, cmd
    if sim == "xcelium":
        cmd = ["xrun", "-compile", "-uvm", "-uvmhome", "CDNS-1.2", "-sv",
               "-timescale", "1ns/1ps", "-l", "comp.log", "-f", str(filelist)]
        return None, cmd
    raise SystemExit(f"error: unsupported simulator {sim!r}")


def compile_filelist(stage, name, lines, args, mfcu=True, subdir=None):
    """Write a filelist and compile it. `lines` are raw filelist lines
    (+incdir+, +define+, -f, absolute paths)."""
    workdir = Path(args.out) / (subdir or f"{stage}_{name}")
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True, exist_ok=True)
    filelist = workdir / "comp_filelist.f"
    filelist.write_text("\n".join(lines) + "\n")

    t0 = time.time()
    setup, cmd = compile_cmds(args.sim, filelist, mfcu=mfcu)
    log = workdir / "comp.log"
    if setup:
        rc = run(setup, workdir, workdir / "setup.log", env=sim_env())
        if rc:
            return Result(stage, name, "FAIL", time.time() - t0, workdir / "setup.log",
                          f"{setup[0]} failed")
    rc = run(cmd, workdir, log, env=sim_env())
    key = "questa" if args.sim in ("questa", "modelsim") else args.sim
    errors, warnings, first = scan_log(log, COMP_FAIL[key], COMP_WARN[key], COMP_WAIVE[key])
    secs = time.time() - t0
    if rc or errors:
        return Result(stage, name, "FAIL", secs, log, first or f"exit {rc}")
    if warnings and args.pedant:
        return Result(stage, name, "FAIL", secs, log, f"{warnings} warning(s), --pedant")
    note = f"{warnings} warning(s)" if warnings else ""
    return Result(stage, name, "PASS", secs, log, note)


_ENV = None


def sim_env():
    """os.environ plus whatever bin/setenv.sh exports (OVIP_ROOT, mainly) --
    the VIP filelists expand $OVIP_ROOT at compile time."""
    global _ENV
    if _ENV is None:
        env = dict(os.environ)
        setenv = REPO / "bin" / "setenv.sh"
        if setenv.is_file():
            proc = subprocess.run(["bash", "-c", f"set -a && source {setenv} && env -0"],
                                  capture_output=True, text=True)
            if proc.returncode == 0:
                for entry in proc.stdout.split("\0"):
                    key, sep, value = entry.partition("=")
                    if sep:
                        env[key] = value
        env.setdefault("OVIP_ROOT", str(REPO))
        _ENV = env
    return _ENV


# ----------------------------------------------------------------------
# Testbench blocks (reuse the test runner's config.yaml parsing)
# ----------------------------------------------------------------------
def testbench_blocks():
    return sorted(d for d in VERIF.glob("ovip_*_testbench") if (d / "lib" / "config.yaml").is_file())


def block_attributes(block_dir):
    """(incdirs, defines, files, comp_args) for a verif block, exactly as the
    test runner would build them."""
    sys.path.insert(0, str(REPO / "bin" / "runners"))
    try:
        from proj_utils import parse_attributes
        with open(os.devnull, "w") as devnull, contextlib.redirect_stdout(devnull):
            attrs = parse_attributes(
                block_dir.name, "verif",
                ["include_dirs", "defines", "files", "comp_args"],
                {"TOOL": "vsim", "WA_ROOT": str(REPO), "TOP_BLOCK": block_dir.name,
                 **os.environ})
    finally:
        sys.path.pop(0)
    return (attrs["include_dirs"], attrs["defines"], attrs["files"], attrs["comp_args"])


def block_filelist_lines(block_dir, drop_tops=False):
    incdirs, defines, files, comp_args = block_attributes(block_dir)
    if drop_tops:
        files = [f for f in files if Path(f).name != "tb.sv"]
    return (list(comp_args)
            + [f"+define+{d}" for d in defines]
            + [f"+incdir+{d}" for d in incdirs]
            + list(files))


# ----------------------------------------------------------------------
# Stages
# ----------------------------------------------------------------------
def stage_vip(vips, args):
    jobs = []
    for short, vip in vips.items():
        if not vip.filelist.is_file():
            jobs.append(lambda s=short: Result("vip", s, "SKIP", 0.0, None, "no filelist"))
            continue
        jobs.append(lambda v=vip, s=short: compile_filelist(
            "vip", s, [f"-f {v.filelist}"], args))
    return jobs


def stage_combined(vips, args):
    lines = [f"-f {v.filelist}" for v in vips.values() if v.filelist.is_file()]
    if not lines:
        return [lambda: Result("combined", "all_vips", "SKIP", 0.0, None, "no filelists")]
    # Testbench packages too, minus the tb.sv tops (all called 'tb').
    wanted = {v.tb_dir.name for v in vips.values()}
    for block in testbench_blocks():
        if block.name in wanted:
            lines += block_filelist_lines(block, drop_tops=True)
    return [lambda: compile_filelist("combined", "all_vips", lines, args,
                                     subdir="combined_all_vips")]


def stage_tb(vips, args):
    jobs = []
    wanted = {v.tb_dir.name for v in vips.values()}
    for block in testbench_blocks():
        if block.name not in wanted:
            continue
        # Parsed here rather than inside the worker: the config parser writes to
        # stdout, and the redirect that silences it is process-wide.
        lines = block_filelist_lines(block)
        name = block.name.replace("ovip_", "").replace("_testbench", "")
        jobs.append(lambda n=name, l=lines: compile_filelist("tb", n, l, args))
    for short, vip in vips.items():
        if not vip.has_testbench:
            jobs.append(lambda s=short: Result("tb", s, "SKIP", 0.0, None, "no testbench"))
    return jobs


def eda_bundle_and_compile(vip_short, args, mfcu):
    """Generate the Playground bundle for one VIP ('all' for the every-VIP
    bundle) and compile it the way EDA Playground would: every uploaded file
    handed to the compiler at once."""
    stage = "eda"
    name = f"{vip_short}{'_mfcu' if mfcu else '_fcu'}"
    workdir = Path(args.out) / f"{stage}_{name}"
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir(parents=True, exist_ok=True)
    bundle = workdir / "bundle"

    t0 = time.time()
    gen_log = workdir / "bundle.log"
    rc = run([sys.executable, str(BUNDLER), "--vip", vip_short, "--out", str(bundle), "--clean"],
             REPO, gen_log, env=sim_env())
    if rc:
        return Result(stage, name, "FAIL", time.time() - t0, gen_log, "bundler failed")

    # The Playground has no include path: every file sits next to the others,
    # so compile from inside the bundle directory with bare file names.
    files = sorted(p.name for p in bundle.glob("eda_*.sv"))
    lines = files
    filelist = bundle / "comp_filelist.f"
    filelist.write_text("\n".join(lines) + "\n")

    setup, cmd = compile_cmds(args.sim, filelist.name, mfcu=mfcu)
    if setup:
        rc = run(setup, bundle, workdir / "setup.log", env=sim_env())
        if rc:
            return Result(stage, name, "FAIL", time.time() - t0, workdir / "setup.log",
                          "vlib failed")
    log = bundle / "comp.log"
    rc = run(cmd, bundle, log, env=sim_env())
    key = "questa" if args.sim in ("questa", "modelsim") else args.sim
    errors, warnings, first = scan_log(log, COMP_FAIL[key], COMP_WARN[key], COMP_WAIVE[key])
    secs = time.time() - t0
    if rc or errors:
        return Result(stage, name, "FAIL", secs, log, first or f"exit {rc}")
    if warnings and args.pedant:
        return Result(stage, name, "FAIL", secs, log, f"{warnings} warning(s), --pedant")

    # A bundle that compiles but lost its top module is useless on the
    # Playground, and the compiler is happy to let that through.
    top = bundle_top_module(gen_log)
    if key == "questa" and top and not compiled_tops(log).issuperset({top}):
        return Result(stage, name, "FAIL", secs, log,
                      f"top module '{top}' is not in the compiled library")

    note = f"{len(files)} files, top {top}"
    if args.run and not mfcu:
        rc = run(["vsim", "-c", "-work", "work", "-do", "run -all; quit", top],
                 bundle, bundle / "run.log", env=sim_env())
        errors, _, first = scan_log(bundle / "run.log", RUN_FAIL, [], COMP_WAIVE[key])
        secs = time.time() - t0
        if rc or errors:
            return Result(stage, name, "FAIL", secs, bundle / "run.log", first or f"exit {rc}")
        note += ", ran clean"
    return Result(stage, name, "PASS", secs, log, note)


def bundle_top_module(gen_log):
    """The top module the bundler reported for this bundle."""
    m = re.search(r"top module: (\w+)", Path(gen_log).read_text(errors="replace"))
    return m.group(1) if m else ""


def compiled_tops(comp_log):
    """Module names Questa listed under 'Top level modules'."""
    text = Path(comp_log).read_text(errors="replace")
    m = re.search(r"Top level modules:\n((?:\s+\S+\n)+)", text)
    return set(m.group(1).split()) if m else set()


def stage_eda(vips, args):
    subjects = list(vips)
    if len(vips) > 1:
        # One bundle with every VIP in it -- the upload used to check the whole
        # family on a simulator we do not have locally.
        subjects.append("all")
    jobs = []
    for subject in subjects:
        for mfcu in (False, True):
            jobs.append(lambda s=subject, m=mfcu: eda_bundle_and_compile(s, args, m))
    return jobs


def run_example(example_dir, args):
    name = f"{example_dir.parent.name}/{example_dir.name}"
    log = Path(args.out) / "examples" / f"{example_dir.parent.name}_{example_dir.name}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    sim = {"questa": "modelsim", "modelsim": "modelsim"}.get(args.sim, args.sim)
    t0 = time.time()
    rc = run(["make", "run", f"SIM={sim}"], example_dir, log, env=sim_env())
    key = "questa" if args.sim in ("questa", "modelsim") else args.sim
    errors, warnings, first = scan_log(log, COMP_FAIL[key] + RUN_FAIL,
                                       COMP_WARN[key], COMP_WAIVE[key])
    secs = time.time() - t0
    if rc or errors:
        return Result("examples", name, "FAIL", secs, log, first or f"exit {rc}")
    if warnings and args.pedant:
        return Result("examples", name, "FAIL", secs, log, f"{warnings} warning(s), --pedant")
    return Result("examples", name, "PASS", secs, log, "compiled + ran")


def stage_examples(vips, args):
    jobs = []
    for vip in vips.values():
        for makefile in sorted(vip.examples.glob("*/Makefile")):
            jobs.append(lambda d=makefile.parent: run_example(d, args))
    return jobs


STAGE_FUNCS = {
    "vip": stage_vip,
    "combined": stage_combined,
    "tb": stage_tb,
    "eda": stage_eda,
    "examples": stage_examples,
}


# ----------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--stages", default=",".join(DEFAULT_STAGES),
                   help=f"comma-separated subset of {ALL_STAGES}, or 'all' "
                        f"(default: {','.join(DEFAULT_STAGES)})")
    p.add_argument("--vip", action="append", default=None,
                   help="limit to this VIP (short name, repeatable). "
                        "Default: every VIP in the repo.")
    p.add_argument("--sim", default="questa",
                   choices=["questa", "modelsim", "vcs", "xcelium"],
                   help="simulator to build with (default: questa)")
    p.add_argument("--out", default=str(DEFAULT_OUT),
                   help=f"where to put libraries and logs (default: {DEFAULT_OUT})")
    p.add_argument("-j", "--jobs", type=int, default=4,
                   help="parallel compiles (default: 4)")
    p.add_argument("--pedant", action="store_true",
                   help="treat compile warnings as failures")
    p.add_argument("--run", action="store_true",
                   help="also simulate each EDA bundle's default test "
                        "(~6s per VIP); the 'examples' stage always runs")
    p.add_argument("--keep", action="store_true",
                   help="keep the output directory from the previous run")
    args = p.parse_args()

    stages = ALL_STAGES if args.stages == "all" else [s.strip() for s in args.stages.split(",")]
    for s in stages:
        if s not in ALL_STAGES:
            raise SystemExit(f"error: unknown stage {s!r}; available: {', '.join(ALL_STAGES)}")

    vips = discover_vips()
    if args.vip:
        missing = [v for v in args.vip if v not in vips]
        if missing:
            raise SystemExit(f"error: unknown VIP(s) {missing}; available: {', '.join(vips)}")
        vips = {k: v for k, v in vips.items() if k in args.vip}

    out = Path(args.out)
    if out.is_dir() and not args.keep:
        shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True, exist_ok=True)

    print(f"compile_check: sim={args.sim}  vips={', '.join(vips)}  stages={', '.join(stages)}")
    print(f"               logs under {out}\n")

    results = []
    for stage in stages:
        jobs = STAGE_FUNCS[stage](vips, args)
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            for res in pool.map(lambda j: j(), jobs):
                colour = {"PASS": GREEN, "FAIL": RED, "SKIP": GREY}[res.status]
                extra = f"  {res.note}" if res.note else ""
                print(f"  {colour}{res.status:<4}{RESET} {res.stage:<9} {res.name:<34} "
                      f"{res.seconds:6.1f}s{GREY}{extra}{RESET}")
                results.append(res)

    failed = [r for r in results if not r.ok]
    print()
    print(f"{len(results) - len(failed)}/{len(results)} passed")
    if failed:
        print(f"\n{RED}failures:{RESET}")
        for r in failed:
            print(f"  {r.stage}/{r.name}: {r.note}")
            print(f"    log: {r.log}")
        return 1
    print(f"{GREEN}all good{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
