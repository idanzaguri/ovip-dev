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

Each body chunk is guarded with `ifdef`s so it is a no-op when EDA Playground
compiles it standalone, and only emits its content when included from the
matching package wrapper in eda_00_top.sv. This sidesteps the "class at top
level, no package, no imports" compile failure that would otherwise hit every
standalone body file.

The VIP layout is discovered from the repo, so this works for every VIP under
verif/ (ovip_axi, ovip_apb, ovip_axi_stream, ovip_ace, ...) and picks up new
source files automatically. Inter-VIP dependencies are read from the VIP's
compile filelist (ovip_ace.f pulls in ovip_axi.f, so an ACE bundle carries the
AXI package too).

Usage:
    python3 tools/bundle_for_eda.py --list
    python3 tools/bundle_for_eda.py --vip axi --out eda_bundle/
    python3 tools/bundle_for_eda.py --vip ace --top example --out eda_bundle_ace/
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

# Every generated file except eda_tb.sv is wrapped in this guard, so the bundle
# compiles the same whether the Playground passes the uploaded files to the
# compiler or only makes them available for `include.
BUNDLE_GUARD = "OVIP_EDA_BUNDLE"

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


def render_eda_tb(vip, defines, tests, top_module, uvm_version="1.2"):
    out = []
    out.append("// ===== eda_tb.sv =====\n")
    out.append("// Auto-generated by tools/bundle_for_eda.py.\n")
    out.append(f"// Paste this file into the EDA Playground 'testbench.sv' pane and\n")
    out.append("// upload every other eda_*.sv from this directory via 'Add file'.\n")
    out.append("//\n")
    out.append("// EDA Playground settings:\n")
    out.append(f"//     UVM / OVM:    UVM {uvm_version}\n")
    out.append(f"//     Top module:   {top_module}\n")
    out.append("//     Tools:        any UVM-1.2 capable simulator\n")
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
    out.append(f"`define {BUNDLE_GUARD}\n")
    out.append('`include "eda_00_top.sv"\n')
    return "".join(out)


# ----------------------------------------------------------------------
def build(vip, vips, out_dir, top_mode, active_test=None):
    chain = vip_chain(vip, vips)
    search = []
    for v in chain:
        search += v.search_dirs()
    search += [COMMON_SRC, MEM_SRC]
    if vip.has_testbench:
        search.append(vip.tb_dir / "src")

    visited = set()
    outer = ["// ===== eda_00_top.sv =====\n",
             "// Auto-generated by tools/bundle_for_eda.py"
             f" (VIP: {vip.name}).\n"
             "// Like the body chunks, this file only emits content when included\n"
             f"// from eda_tb.sv (which defines {BUNDLE_GUARD} first), so it stays a\n"
             "// no-op if the Playground also hands it to the compiler directly.\n"
             f"`ifdef {BUNDLE_GUARD}\n\n",
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

    # Then the top: either the VIP's testbench (tests package + tb.sv) or a
    # standalone example file.
    tests, top_module = [], "tb"
    if top_mode == "testbench":
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

    outer.append(f"\n`endif // {BUNDLE_GUARD}\n")

    outer_text = "".join(outer)
    (out_dir / "eda_00_top.sv").write_text(outer_text)
    written = [("eda_00_top.sv", len(outer_text))]
    for name, text in chunk_files:
        (out_dir / name).write_text(text)
        written.append((name, len(text)))

    tb_text = render_eda_tb(vip, load_testbench_defines(vip), tests, top_module)
    (out_dir / "eda_tb.sv").write_text(tb_text)
    written.append(("eda_tb.sv", len(tb_text)))
    return written, top_module


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--vip", default="axi",
                   help="which VIP to bundle, by short name (default: axi). "
                        "Use --list to see the available ones.")
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
        print("VIPs available for bundling:")
        for short, v in vips.items():
            tb = "testbench" if v.has_testbench else "-"
            ex = ", ".join(str(e.relative_to(REPO)) for e in v.example_files) or "-"
            print(f"  {short:<12} pkg={v.pkg_file.relative_to(REPO)}\n"
                  f"  {'':<12} top={tb}\n"
                  f"  {'':<12} examples={ex}")
        return

    if args.vip not in vips:
        raise SystemExit(f"error: unknown VIP {args.vip!r}; available: {', '.join(vips)}")
    vip = vips[args.vip]

    if args.top == "testbench" and not vip.has_testbench:
        raise SystemExit(f"error: {vip.name} has no testbench under verif/{vip.name}_testbench")
    top_mode = args.top
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
    print(f"Wrote {len(written)} files to {out_dir}  (VIP: {vip.name}, top module: {top_module})")
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
    print("Compile the bundle locally first with: "
          f"python3 tools/compile_check.py --stages eda --vip {vip.short}")


if __name__ == "__main__":
    main()
