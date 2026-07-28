#!/usr/bin/env python3
"""Bundle an OVIP VIP for EDA Playground in a few chunk files (each <100KB).

EDA Playground caps a single source file at 100KB and has no include path of
its own, so the VIP has to be flattened and split. This script produces:

  - eda_tb.sv         : the file you paste into the Playground "testbench.sv"
                        pane. Sets the compile-time defines, picks the test to
                        run, and `include`s eda_00_top.sv.
  - eda_00_top.sv     : the OUTER wrapper -- package/interface/module
                        declarations, with `include directives pointing to the
                        body chunks. Small (well under the cap).
  - eda_NN_*_body_*.sv: chunks of class declarations (concatenated original
                        files), each <95KB.

Playground compiles design.sv and testbench.sv only; uploaded files are there
to be `include`d, never handed to the compiler. So eda_tb.sv pulls in the whole
bundle, and only two properties matter:

  - eda_00_top.sv is self-sufficient (plain include guard, no dependency on a
    macro set elsewhere). Pasting it into a pane by mistake then still yields
    the design and one top module instead of compiling to nothing, which the
    simulator would report as the thoroughly unhelpful "no top-level unit
    found".
  - each body chunk stays guarded on its package's *_BODY macro, so it emits
    only from inside the matching package wrapper. That sidesteps the "class at
    top level, no package, no imports" failure a standalone chunk would hit.

The VIP layout is discovered from the repo, so this works for every VIP under
verif/ (ovip_axi, ovip_apb, ovip_axi_stream, ovip_ace, ...) and picks up new
source files automatically. Inter-VIP dependencies are read from the VIP's
compile filelist (ovip_ace.f pulls in ovip_axi.f, so an ACE bundle carries the
AXI package too).

--vip all bundles every VIP at once behind a generated top that instantiates
each VIP's interface and finishes. It runs no test: it is the "does the whole
family build on this simulator?" upload, for checking OVIP against simulators
you do not have a licence for locally.

Usage:
    python3 tools/bundle_for_eda.py --list
    python3 tools/bundle_for_eda.py --vip axi --out eda_bundle/
    python3 tools/bundle_for_eda.py --vip ace --top example --out eda_bundle_ace/
    python3 tools/bundle_for_eda.py --vip all --out eda_bundle_all/
    # upload every eda_bundle/eda_*.sv to EDA Playground via 'Add file',
    # and paste eda_tb.sv into the testbench.sv pane

The generated eda_tb.sv carries the EDA Playground settings (UVM version, top
module, defines, test list) in its header comment.
"""

import argparse
import contextlib
import os
import re
import shutil
import sys
from pathlib import Path

REPO       = Path(__file__).resolve().parent.parent
VERIF      = REPO / "verif"
COMMON_SRC = VERIF / "ovip_common"
MEM_SRC    = COMMON_SRC / "mem"
EXAMPLES   = REPO / "examples"

MAX_CHUNK    = 95_000   # safe margin under EDA Playground's 100KB cap
INLINE_LIMIT = 20_000   # package bodies smaller than this go into eda_00_top.sv

# eda_00_top.sv carries a plain include guard, so pasting it into a Playground
# pane works and compiling it twice in one compilation unit is harmless. It must
# NOT be guarded on a macro that only eda_tb.sv defines: a file that compiles to
# nothing fails as "no top-level unit found", which says nothing about the cause.
TOP_GUARD = "OVIP_EDA_TOP__SV"

INCLUDE_RE    = re.compile(r'^\s*`include\s*"([^"]+)"')
PACKAGE_RE    = re.compile(r'^\s*package\s+(\w+)\s*;')
ENDPACKAGE_RE = re.compile(r'^\s*endpackage\b')
CLASS_RE      = re.compile(r'^\s*class\s+(\w+)\s+extends\b')
FILELIST_F_RE = re.compile(r'^\s*-f\s+\S*[/\\]verif[/\\](ovip_\w+)[/\\]')

# `include directives left alone (the simulator supplies them).
PASSTHRU = {"uvm_macros.svh"}
# Optional per-project hook files that are deliberately absent from the repo;
# they sit behind an `ifdef, so leaving the directive in place is correct.
PASSTHRU_RE = re.compile(r'_user_defines\.sv$')


def read(path):
    return Path(path).read_text()


def is_passthru(inc):
    return inc in PASSTHRU or PASSTHRU_RE.search(inc) is not None


def resolve(fname, search_dirs):
    for d in search_dirs:
        p = Path(d) / fname
        if p.is_file():
            return p
        # fall back to basename if not found by literal path
        p = Path(d) / os.path.basename(fname)
        if p.is_file():
            return p
    return None


def flatten_file(path, search_dirs, visited):
    """Return path's content with all non-PASSTHRU `include directives
    recursively inlined. Handles things like monitor.sv conditionally
    `include'ing monitor_xz_and_stability_functions.sv."""
    abspath = os.path.abspath(str(path))
    if abspath in visited:
        return f"// (re-include skipped: {os.path.basename(str(path))})\n"
    visited.add(abspath)
    here = Path(path).parent
    out = []
    for line in read(path).splitlines(keepends=True):
        m = INCLUDE_RE.match(line)
        if not m:
            out.append(line)
            continue
        inc = m.group(1)
        if is_passthru(inc):
            out.append(line)
            continue
        p = resolve(inc, [here] + search_dirs)
        if not p:
            print(f"warning: cannot resolve `include {inc!r} from {path}", file=sys.stderr)
            out.append(line)
            continue
        out.append(f"// ===== begin include: {inc} =====\n")
        out.append(flatten_file(p, search_dirs, visited))
        out.append(f"// ===== end   include: {inc} =====\n")
    return "".join(out)


# ----------------------------------------------------------------------
# Repo discovery
# ----------------------------------------------------------------------
class Vip:
    """One VIP under verif/: its sources, filelist and (optional) testbench."""

    def __init__(self, directory):
        self.dir      = directory
        self.name     = directory.name                    # e.g. ovip_axi
        self.short    = directory.name[len("ovip_"):]     # e.g. axi
        self.src      = directory / "src"
        self.pkg_file = self.src / f"{self.name}_pkg.sv"
        self.filelist = directory / f"{self.name}.f"
        self.tb_dir   = VERIF / f"{self.name}_testbench"
        self.examples = EXAMPLES / self.name

    @property
    def has_testbench(self):
        return self.tb_dir.is_dir() and self.tests_pkg_file is not None

    @property
    def tests_pkg_file(self):
        cands = sorted((self.tb_dir / "src").glob("*tests_pkg.sv")) if self.tb_dir.is_dir() else []
        return cands[0] if cands else None

    @property
    def tb_top_file(self):
        p = self.tb_dir / "src" / "tb.sv"
        return p if p.is_file() else None

    @property
    def example_files(self):
        if not self.examples.is_dir():
            return []
        return sorted(self.examples.glob("*/*_example.sv"))

    def deps(self):
        """VIP names this VIP's filelist pulls in, in filelist order."""
        if not self.filelist.is_file():
            return []
        out = []
        for line in read(self.filelist).splitlines():
            m = FILELIST_F_RE.match(line)
            if m and m.group(1) != self.name:
                out.append(m.group(1))
        return out

    def search_dirs(self):
        return [self.src, self.src / "seqlib"]


def discover_vips():
    """{short_name: Vip} for every verif/ovip_* directory that has a package."""
    out = {}
    for d in sorted(VERIF.glob("ovip_*")):
        if not d.is_dir() or d.name.endswith("_testbench") or d.name == "ovip_common":
            continue
        vip = Vip(d)
        if vip.pkg_file.is_file():
            out[vip.short] = vip
    return out


def vip_chain(vip, vips):
    """`vip` preceded by its dependencies, dependencies first, deduplicated."""
    chain = []

    def walk(v):
        for dep_name in v.deps():
            dep = vips.get(dep_name[len("ovip_"):])
            if dep:
                walk(dep)
        if v.name not in [c.name for c in chain]:
            chain.append(v)

    walk(vip)
    return chain


def all_vips_chain(vips):
    """Every VIP in the repo, dependencies first, each one once."""
    chain = []
    for vip in vips.values():
        for v in vip_chain(vip, vips):
            if v.name not in [c.name for c in chain]:
                chain.append(v)
    return chain


# ----------------------------------------------------------------------
# Package parsing / emission
# ----------------------------------------------------------------------
class Package:
    """A parsed `package foo; ... endpackage` source file.

    pre/post are the top-level lines around the package (include guard,
    `include of defines/macros/interfaces). head/tail are the non-`include
    lines inside the package (imports). body_files are the `include'd class
    files, which are what gets chunked."""

    def __init__(self, path, pkg_name, pre, head, body_files, tail, post):
        self.path       = path
        self.name       = pkg_name
        self.pre        = pre
        self.head       = head
        self.body_files = body_files
        self.tail       = tail
        self.post       = post


def parse_package(path, search_dirs):
    lines = read(path).splitlines(keepends=True)

    ipkg = next((i for i, l in enumerate(lines) if PACKAGE_RE.match(l)), None)
    if ipkg is None:
        raise SystemExit(f"error: no 'package <name>;' found in {path}")
    pkg_name = PACKAGE_RE.match(lines[ipkg]).group(1)
    iend = next((i for i in range(len(lines) - 1, ipkg, -1) if ENDPACKAGE_RE.match(lines[i])), None)
    if iend is None:
        raise SystemExit(f"error: no 'endpackage' found in {path}")

    inner = lines[ipkg + 1:iend]
    body_files, head, tail = [], [], []
    for line in inner:
        m = INCLUDE_RE.match(line)
        if m and not is_passthru(m.group(1)):
            p = resolve(m.group(1), [path.parent] + list(search_dirs))
            if not p:
                print(f"warning: cannot resolve `include {m.group(1)!r} from {path}", file=sys.stderr)
                continue
            body_files.append(p)
        elif body_files:
            tail.append(line)
        else:
            head.append(line)

    return Package(path, pkg_name, lines[:ipkg], head, body_files, tail, lines[iend:])


def make_chunks(files, guard_macro, chunk_prefix, search_dirs, visited):
    """Concatenate `files` into chunks of <= MAX_CHUNK bytes. Each file's
    content is RECURSIVELY flattened (its own `include directives inlined) so
    nothing within a chunk references files outside the bundle. Each chunk is
    wrapped in `ifdef <guard_macro> ... `endif so it is a no-op when compiled
    standalone. Returns (list of (chunk_basename, text), total_body_bytes)."""
    chunks, current, current_size, idx = [], [], 0, 1
    for f in files:
        body = flatten_file(f, search_dirs, visited)
        if current and current_size + len(body) > MAX_CHUNK:
            chunks.append((f"{chunk_prefix}_{idx:02d}.sv", current))
            idx += 1
            current, current_size = [], 0
        current.append((Path(f).name, body))
        current_size += len(body)
    if current:
        chunks.append((f"{chunk_prefix}_{idx:02d}.sv", current))

    result, total = [], 0
    for name, parts in chunks:
        header = (f"// ===== {name} =====\n"
                  f"// Auto-generated by tools/bundle_for_eda.py.\n"
                  f"// This file's content is only emitted when included from the wrapper\n"
                  f"// (eda_00_top.sv defines {guard_macro} before `including).\n"
                  f"`ifdef {guard_macro}\n")
        footer = f"`endif // {guard_macro}\n"
        body_concat = "".join(f"\n// ----- {fn} -----\n{txt}" for fn, txt in parts)
        result.append((name, header + body_concat + "\n" + footer))
        total += len(body_concat)
    return result, total


def emit_package(pkg, chunk_prefix, search_dirs, visited, outer):
    """Append `pkg` to the outer-wrapper part list. Small bodies are inlined
    into the wrapper; big ones go to chunk files. Returns the chunk list."""
    guard = f"{pkg.name.upper()}_BODY"
    chunks, total = make_chunks(pkg.body_files, guard, chunk_prefix, search_dirs, visited)

    outer.append(f"\n// ================= {pkg.path.name} =================\n")
    for line in pkg.pre:
        m = INCLUDE_RE.match(line)
        if not m or is_passthru(m.group(1)):
            outer.append(line)
            continue
        p = resolve(m.group(1), [pkg.path.parent] + list(search_dirs))
        if not p:
            print(f"warning: cannot resolve `include {m.group(1)!r} from {pkg.path}", file=sys.stderr)
            outer.append(line)
            continue
        outer.append(f"// ----- inlined: {m.group(1)} -----\n")
        outer.append(flatten_file(p, search_dirs, visited))
        outer.append(f"// ----- end {m.group(1)} -----\n")

    outer.append(f"package {pkg.name};\n")
    outer.extend(pkg.head)
    if total <= INLINE_LIMIT:
        # Small package -- no point spending a chunk file on it.
        for _, text in chunks:
            # strip the `ifdef guard: the content lands inside the package already
            body = text.split("\n", 5)[-1].rsplit("`endif", 1)[0]
            outer.append(body)
        chunks = []
    else:
        outer.append(f"\t`define {guard}\n")
        for name, _ in chunks:
            outer.append(f'\t`include "{name}"\n')
        outer.append(f"\t`undef {guard}\n")
    outer.extend(pkg.tail)
    outer.extend(pkg.post)
    return chunks


# ----------------------------------------------------------------------
# eda_tb.sv (the Playground "testbench.sv" pane)
# ----------------------------------------------------------------------
def collect_test_names(pkg, search_dirs):
    """UVM test class names declared in a tests package, base tests last."""
    names = []
    for f in pkg.body_files:
        for line in read(f).splitlines():
            m = CLASS_RE.match(line)
            if m and m.group(1).endswith("_test"):
                names.append(m.group(1))
    concrete = sorted(n for n in names if "base_test" not in n)
    return concrete


def interface_of(vip):
    """(interface name, port names) of the VIP's agent interface, or None."""
    cands = sorted(vip.src.glob("*agent_if.sv"))
    if not cands:
        return None
    m = re.search(r'^\s*interface\s+(\w+)\s*\(([^)]*)\)\s*;', read(cands[0]), re.M)
    if not m:
        return None
    ports = re.findall(r'(\w+)\s*(?:,|$)', m.group(2).strip())
    return m.group(1), ports


def render_all_vips_top(chain):
    """A top module that instantiates every VIP's interface and finishes.

    The all-VIP bundle exists to answer one question -- does the whole family
    build and elaborate on this simulator -- so this top drives no traffic and
    starts no UVM test. Interfaces whose port list is not the usual
    (clock, reset_n) pair are left out rather than guessed at."""
    ifaces, skipped = [], []
    for v in chain:
        info = interface_of(v)
        if info and len(info[1]) == 2:
            ifaces.append((v, info[0]))
        else:
            skipped.append(v.name)

    out = ["`timescale 1ns/1ps\n\n",
           "// Generated by tools/bundle_for_eda.py --vip all.\n",
           "// Compiles and elaborates every OVIP VIP side by side; it drives no\n",
           "// traffic and runs no UVM test. If this passes on a simulator, the\n",
           "// whole VIP family builds on it.\n",
           "module tb;\n"]
    for v in chain:
        out.append(f"\timport {v.name}_pkg::*;\n")
    out.append("\n\tlogic clk = 0, rstn = 0;\n")
    out.append("\talways #500ps clk = ~clk;\n\n")
    for v, iface in ifaces:
        out.append(f"\t{iface} {v.short}_if(clk, rstn);\n")
    for name in skipped:
        out.append(f"\t// {name}: no two-port agent interface found, not instantiated\n")
    out.append("\n\tinitial begin\n")
    out.append("\t\trepeat (4) @(posedge clk);\n")
    out.append("\t\trstn = 1;\n")
    out.append("\t\trepeat (4) @(posedge clk);\n")
    names = ", ".join(v.name for v in chain)
    out.append(f'\t\t$display("OVIP: compiled and elaborated {names}");\n')
    out.append("\t\t$finish;\n")
    out.append("\tend\n")
    out.append("endmodule : tb\n")
    return "".join(out)


def load_testbench_defines(vip):
    """Compile-time defines the local testbench uses (verif/<tb>/lib/config.yaml),
    so the Playground build matches it. Best-effort: the parser lives in
    bin/runners and needs jinja2/pyyaml, which the Playground bundle does not."""
    if not vip.has_testbench:
        return []
    sys.path.insert(0, str(REPO / "bin" / "runners"))
    try:
        from proj_utils import parse_attributes
        # parse_attributes chatters about every path it resolves; that noise is
        # for the test runner, not for us.
        with open(os.devnull, "w") as devnull, contextlib.redirect_stdout(devnull):
            attrs = parse_attributes(vip.tb_dir.name, "verif", ["defines"],
                                     {"TOOL": "vsim", "WA_ROOT": str(REPO),
                                      "TOP_BLOCK": vip.tb_dir.name, **os.environ})
        return list(attrs["defines"])
    except Exception as e:                                  # noqa: BLE001
        print(f"warning: could not read testbench defines ({e}); "
              f"generating eda_tb.sv without them", file=sys.stderr)
        return []
    finally:
        sys.path.pop(0)


def render_eda_tb(subject, defines, tests, top_module, uvm_version="1.2"):
    out = []
    out.append("// ===== eda_tb.sv =====\n")
    out.append(f"// Auto-generated by tools/bundle_for_eda.py ({subject}).\n")
    out.append("// HOW TO USE THIS ON EDA PLAYGROUND\n")
    out.append("//   1. Paste THIS file, and only this file, into the 'testbench.sv'\n")
    out.append("//      pane. Leave the 'design.sv' pane empty.\n")
    out.append("//   2. Upload every OTHER eda_*.sv from this directory via 'Add file',\n")
    out.append("//      keeping the names exactly as they are. Playground compiles only\n")
    out.append("//      design.sv and testbench.sv; the uploads are pulled in by the\n")
    out.append("//      `include below, which is why the names have to match.\n")
    out.append(f"//   3. UVM / OVM: UVM {uvm_version}. Top module: {top_module}.\n")
    out.append("//      Any UVM-1.2 capable simulator will do.\n")
    out.append("//\n")
    out.append("// If the run reports no top-level unit, a file other than this one\n")
    out.append("// ended up in the pane, or an upload is missing or misnamed.\n")
    out.append("//\n")
    if tests:
        out.append("// Pick the test to run by uncommenting exactly one TEST_NAME below.\n")
    out.append("\n")
    for d in defines:
        name, _, value = d.partition("=")
        out.append(f"`define {name}{(' ' + value) if value else ''}\n")
    if defines:
        out.append("\n")
    for i, t in enumerate(tests):
        prefix = "" if i == 0 else "//"
        out.append(f'{prefix}`define TEST_NAME "{t}"\n')
    if tests:
        out.append("\n")
    out.append('`include "eda_00_top.sv"\n')
    return "".join(out)


# ----------------------------------------------------------------------
def build(vip, vips, out_dir, top_mode, active_test=None):
    chain = all_vips_chain(vips) if top_mode == "all" else vip_chain(vip, vips)
    search = []
    for v in chain:
        search += v.search_dirs()
    search += [COMMON_SRC, MEM_SRC]
    if vip and vip.has_testbench:
        search.append(vip.tb_dir / "src")

    label = "every VIP" if top_mode == "all" else vip.name
    visited = set()
    outer = ["// ===== eda_00_top.sv =====\n",
             "// Auto-generated by tools/bundle_for_eda.py"
             f" (VIP: {label}).\n"
             "// Normally pulled in by eda_tb.sv, but self-sufficient: pasted into a\n"
             "// Playground pane on its own it still yields the whole design and one\n"
             "// top module (run it with +UVM_TESTNAME=... then). The include guard\n"
             "// keeps a second compile in the same compilation unit harmless.\n"
             f"`ifndef {TOP_GUARD}\n"
             f"`define {TOP_GUARD}\n\n",
             # Without this the packages inherit whatever the tool defaults to,
             # which Xcelium reports as *W,TSNSPK. Matches the testbenches.
             "`timescale 1ns/1ps\n\n",
             '`include "uvm_macros.svh"\n']
    chunk_files = []

    # ovip_common first: every VIP package imports it.
    for common_pkg in [COMMON_SRC / "ovip_global_pkg.sv", MEM_SRC / "ovip_mem_pkg.sv"]:
        pkg = parse_package(common_pkg, search)
        chunk_files += emit_package(pkg, f"eda_{pkg.name}_body", search, visited, outer)

    # Then the VIP packages, dependencies first.
    for v in chain:
        pkg = parse_package(v.pkg_file, search)
        chunk_files += emit_package(pkg, f"eda_{v.short}_body", search, visited, outer)

    # Then the top: the VIP's testbench (tests package + tb.sv), a standalone
    # example file, or -- for an all-VIP bundle -- a generated top that just
    # elaborates every VIP side by side.
    tests, top_module = [], "tb"
    if top_mode == "all":
        outer.append("\n// ----- generated all-VIP top -----\n")
        outer.append(render_all_vips_top(chain))
    elif top_mode == "testbench":
        tests_pkg = parse_package(vip.tests_pkg_file, search)
        chunk_files += emit_package(tests_pkg, "eda_tests_body", search, visited, outer)
        tests = collect_test_names(tests_pkg, search)
        if active_test:
            if active_test not in tests:
                raise SystemExit(f"error: no test {active_test!r} in {vip.tests_pkg_file.name}; "
                                 f"available:\n  " + "\n  ".join(tests))
            # The first entry is the one left uncommented in eda_tb.sv.
            tests = [active_test] + [t for t in tests if t != active_test]
        outer.append(f"\n// ----- {vip.tb_top_file.name} -----\n")
        outer.append(flatten_file(vip.tb_top_file, search, visited))
    else:
        example = top_mode
        outer.append(f"\n// ----- {example.name} -----\n")
        outer.append(flatten_file(example, search, visited))
        m = re.search(r'^\s*module\s+(\w+)\s*;', read(example), re.M)
        top_module = m.group(1) if m else "tb_top"

    outer.append(f"\n`endif // {TOP_GUARD}\n")

    outer_text = "".join(outer)
    (out_dir / "eda_00_top.sv").write_text(outer_text)
    written = [("eda_00_top.sv", len(outer_text))]
    for name, text in chunk_files:
        (out_dir / name).write_text(text)
        written.append((name, len(text)))

    if top_mode == "all":
        # No testbench defines: the point of this bundle is that the VIPs build
        # in their out-of-the-box configuration, which is what an adopter gets.
        subject, defines = "every VIP in the repo", []
    else:
        subject, defines = vip.name, load_testbench_defines(vip)
    tb_text = render_eda_tb(subject, defines, tests, top_module)
    (out_dir / "eda_tb.sv").write_text(tb_text)
    written.append(("eda_tb.sv", len(tb_text)))
    return written, top_module


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--vip", default="axi",
                   help="which VIP to bundle, by short name (default: axi), or "
                        "'all' for one bundle holding every VIP with a generated "
                        "top that just elaborates them. Use --list to see them.")
    p.add_argument("--list", action="store_true",
                   help="list the VIPs discovered in this repo and exit")
    p.add_argument("--out", default="eda_bundle",
                   help="output directory (default: eda_bundle)")
    p.add_argument("--clean", action="store_true",
                   help="remove the output directory first")
    p.add_argument("--top", default="auto", choices=["auto", "testbench", "example"],
                   help="what to put on top: the VIP's testbench (full test list) "
                        "or a standalone example. 'auto' prefers the testbench "
                        "(default: auto)")
    p.add_argument("--example", default=None,
                   help="path to the example .sv to use with --top example "
                        "(default: the VIP's first example)")
    p.add_argument("--test", default=None,
                   help="test to leave active in eda_tb.sv (default: the first "
                        "one alphabetically; the rest are listed commented out)")
    args = p.parse_args()

    vips = discover_vips()
    if args.list:
        print("VIPs available for bundling (or --vip all for one bundle with "
              "every VIP):")
        for short, v in vips.items():
            tb = "testbench" if v.has_testbench else "-"
            ex = ", ".join(str(e.relative_to(REPO)) for e in v.example_files) or "-"
            print(f"  {short:<12} pkg={v.pkg_file.relative_to(REPO)}\n"
                  f"  {'':<12} top={tb}\n"
                  f"  {'':<12} examples={ex}")
        return

    if args.vip == "all":
        if args.top != "auto" or args.example or args.test:
            raise SystemExit("error: --vip all has a generated top, so it takes "
                             "neither --top/--example nor --test")
        vip, top_mode = None, "all"
    elif args.vip not in vips:
        raise SystemExit(f"error: unknown VIP {args.vip!r}; "
                         f"available: {', '.join(vips)}, all")
    else:
        vip, top_mode = vips[args.vip], args.top

    if vip and top_mode == "testbench" and not vip.has_testbench:
        raise SystemExit(f"error: {vip.name} has no testbench under verif/{vip.name}_testbench")
    if top_mode == "auto":
        top_mode = "testbench" if vip.has_testbench else "example"
    if top_mode == "example":
        if args.example:
            example = Path(args.example).resolve()
        else:
            cands = vip.example_files
            if not cands:
                raise SystemExit(f"error: no examples found under {vip.examples}")
            example = cands[0]
        if not example.is_file():
            raise SystemExit(f"error: no such example file: {example}")
        top_mode = example

    out_dir = Path(args.out).resolve()
    if args.clean and out_dir.is_dir():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    written, top_module = build(vip, vips, out_dir, top_mode, args.test)

    biggest_name, biggest_size = max(written, key=lambda x: x[1])
    subject = "every VIP" if vip is None else vip.name
    print(f"Wrote {len(written)} files to {out_dir}  (VIP: {subject}, top module: {top_module})")
    print(f"Largest file: {biggest_name} ({biggest_size:,} bytes)")
    if biggest_size > 100_000:
        print(f"WARNING: {biggest_name} exceeds EDA Playground's 100KB cap!", file=sys.stderr)
    else:
        print("All files are under EDA Playground's 100KB-per-file cap.")

    print("\n--- file list ---")
    for n, s in sorted(written):
        print(f"  {s:>7,}  {n}")
    print("\nPaste eda_tb.sv into the Playground 'testbench.sv' pane; "
          "upload the rest via 'Add file'.")
    print("Compile the bundle locally first with: python3 tools/compile_check.py "
          f"--stages eda{'' if vip is None else f' --vip {vip.short}'}")


if __name__ == "__main__":
    main()
