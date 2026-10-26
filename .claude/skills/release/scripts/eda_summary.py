#!/usr/bin/env python3
"""Summarize the EDA Playground logs stored by eda_server.py.

Reads every <bundle>_<sim>__<test>.txt under the logs directory and prints one
line per run: bundle, simulator, test, UVM_ERROR / UVM_FATAL counts, compile
errors, compile warnings that are not on the known-noise list, and a verdict.
Exit code 1 if any run is not PASS or KNOWN.

Usage:
    python3 .claude/skills/release/scripts/eda_summary.py [logs_dir] [--warnings]

Default logs_dir: sim/eda_playground/logs. --warnings also prints the first
line of every warning that is not known noise.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]

# Warnings that are not the VIP's problem (see references/eda-playground.md).
KNOWN_WARNINGS = [
    r"Warning-\[TLRCE\]",      # VCS: repeat (size) in ovip_mem.sv, 64-bit count
    r"\*W,PRPASZ",             # xmsim probe-size notice on uvm_string_to_bits
]
# Tests that hit the Playground runtime cap by design. None since ovip_mem_test
# fits its benchmark to the cap (OVIP_EDA_PLAYGROUND); an interrupted run fails.
KNOWN_INTERRUPTED = set()

COMP_ERR = re.compile(r"^(Error-\[|\*E,|\*F,|xmvlog: \*E|xmelab: \*E)", re.M)
COMP_WARN = re.compile(r"^(Warning-\[.*|\*W,.*|xmsim: \*W,.*|xmelab: \*W,.*|xmvlog: \*W,.*)$", re.M)


def grab(txt, pat):
    m = re.search(pat, txt)
    return int(m.group(1)) if m else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    show_warnings = "--warnings" in sys.argv
    logs = Path(args[0]) if args else REPO / "sim" / "eda_playground" / "logs"
    files = sorted(p for p in logs.glob("*__*.txt"))
    if not files:
        print(f"no run logs under {logs}")
        return 1

    rows, bad = [], 0
    for p in files:
        tag, test = p.stem.split("__", 1)
        bundle, _, sim = tag.rpartition("_")
        txt = p.read_text(errors="replace")
        err, fatal = grab(txt, r"UVM_ERROR :\s+(\d+)"), grab(txt, r"UVM_FATAL :\s+(\d+)")
        cerr = len(COMP_ERR.findall(txt))
        warns = [w for w in COMP_WARN.findall(txt) if not any(re.search(k, w) for k in KNOWN_WARNINGS)]
        interrupted = "Execution interrupted" in txt
        done = re.search(r"(^|\n)Done\s*$", txt) is not None   # Xcelium prints "Loading snapshot ... Done" too
        finished = "$finish" in txt or "Simulation complete" in txt or "OVIP: compiled and elaborated" in txt

        if interrupted:
            verdict = "KNOWN" if test in KNOWN_INTERRUPTED else "FAIL"
        elif cerr or err or fatal or (err is None and not finished) or not done:
            verdict = "FAIL"
        else:
            verdict = "PASS"
        if verdict == "FAIL":
            bad += 1
        rows.append((bundle, sim, test, err, fatal, cerr, len(warns), verdict, warns))

    w = max(len(r[2]) for r in rows)
    print(f"{'bundle':<11}{'sim':<9}{'test':<{w + 2}}{'err':>4}{'fatal':>6}{'cerr':>5}{'warn':>5}  verdict")
    for bundle, sim, test, err, fatal, cerr, nw, verdict, warns in rows:
        e = "-" if err is None else err
        f = "-" if fatal is None else fatal
        print(f"{bundle:<11}{sim:<9}{test:<{w + 2}}{e:>4}{f:>6}{cerr:>5}{nw:>5}  {verdict}")
        if show_warnings:
            for line in warns:
                print(f"{'':<20}  {line.strip()[:110]}")

    n = len(rows)
    print(f"\n{n - bad}/{n} runs PASS or KNOWN; {bad} FAIL")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
