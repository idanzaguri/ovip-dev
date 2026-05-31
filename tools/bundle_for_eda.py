#!/usr/bin/env python3
"""Bundle the VIP for EDA Playground in a few chunk files (each <100KB).

EDA Playground caps a single source file at 100KB, so a single-file flatten
(~290KB) won't fit. This script produces a small number of chunk files
arranged so:

  - eda_00_top.sv     : the OUTER wrapper -- package/interface/module
                        declarations, with `include directives pointing
                        to the body chunks. Small (well under the cap).
  - eda_NN_*_body_*.sv: chunks of class declarations (concatenated
                        original files), each <95KB.

Each body chunk is guarded with `\`ifdef`s so it is a no-op when EDA
Playground compiles it standalone, and only emits its content when
included from the matching package wrapper in eda_00_top.sv. This sidesteps
the "class at top level, no package, no imports" compile failure that
would otherwise hit every standalone body file.

Usage:
    python3 tools/bundle_for_eda.py --out eda_bundle/
    # upload every eda_bundle/eda_*.sv to EDA Playground via 'Add file'

On EDA Playground:
    UVM:          1.2
    Top module:   tb
    Compile flag: +define+TEST_BUS_WIDTH_BYTES=8
                  (X/Z + signal-stability checks are ON by default; add
                   +define+OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS to opt out)
    Runtime arg:  +UVM_TESTNAME=<test class name>
"""

import argparse
import os
import re
import shutil
import sys
from pathlib import Path

REPO    = Path(__file__).resolve().parent.parent
VIP_SRC    = REPO / "verif/ovip_axi/src"
SEQ_SRC    = VIP_SRC / "seqlib"
COMMON_SRC = REPO / "verif/ovip_common"
MEM_SRC    = COMMON_SRC / "mem"
TB_SRC  = REPO / "verif/ovip_axi_testbench/src"

MAX_CHUNK = 95_000  # safe margin under EDA Playground's 100KB cap

INCLUDE_RE = re.compile(r'^\s*`include\s*"([^"]+)"')

# `include directives left alone (the simulator supplies them).
PASSTHRU = {"uvm_macros.svh"}


def read(path):
    return Path(path).read_text()


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


def collect_includes_of(path, search_dirs):
    """Return the ordered list of files `include'd from `path` (one level deep),
    skipping pass-thru names."""
    out = []
    for line in read(path).splitlines():
        m = INCLUDE_RE.match(line)
        if not m:
            continue
        name = m.group(1)
        if name in PASSTHRU:
            continue
        p = resolve(name, search_dirs)
        if p:
            out.append(p)
        else:
            print(f"warning: cannot resolve `include {name!r} from {path}", file=sys.stderr)
    return out


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
        if inc in PASSTHRU:
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


def make_chunks(files, guard_macro, chunk_prefix, max_bytes, search_dirs):
    """Concatenate `files` into chunks of <= max_bytes. Each top-level file's
    content is RECURSIVELY flattened (its own `include directives inlined)
    so nothing within a chunk references files outside the bundle. Each chunk
    is wrapped in `ifdef <guard_macro> ... `endif so it is a no-op when
    compiled standalone. Returns list of (chunk_basename, text)."""
    visited = set()
    chunks = []
    current = []
    current_size = 0
    idx = 1
    for f in files:
        body = flatten_file(f, search_dirs, visited)
        if current and current_size + len(body) > max_bytes:
            chunks.append((f"{chunk_prefix}_{idx:02d}.sv", current))
            idx += 1
            current = []
            current_size = 0
        current.append((Path(f).name, body))
        current_size += len(body)
    if current:
        chunks.append((f"{chunk_prefix}_{idx:02d}.sv", current))

    result = []
    for name, parts in chunks:
        header = (f"// ===== {name} =====\n"
                  f"// Auto-generated by tools/bundle_for_eda.py.\n"
                  f"// This file's content is only emitted when included from the wrapper\n"
                  f"// (eda_00_top.sv defines {guard_macro} before `including).\n"
                  f"`ifdef {guard_macro}\n")
        footer = f"`endif // {guard_macro}\n"
        body_concat = "".join(
            f"\n// ----- {fn} -----\n{txt}" for fn, txt in parts)
        result.append((name, header + body_concat + "\n" + footer))
    return result


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--out", default="eda_bundle",
                   help="output directory (default: eda_bundle)")
    p.add_argument("--clean", action="store_true",
                   help="remove the output directory first")
    args = p.parse_args()

    out_dir = Path(args.out).resolve()
    if args.clean and out_dir.is_dir():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    search = [VIP_SRC, SEQ_SRC, COMMON_SRC, MEM_SRC, TB_SRC]

    # Discover the body files for each big package by walking its wrapper.
    vip_body_files   = collect_includes_of(VIP_SRC / "ovip_axi_pkg.sv", search)
    tests_body_files = collect_includes_of(TB_SRC / "ovip_tests_pkg.sv", search)

    # Build chunked body files.
    vip_chunks   = make_chunks(vip_body_files,   "OVIP_AXI_PKG_BODY",
                               "eda_vip_body",   MAX_CHUNK, search)
    tests_chunks = make_chunks(tests_body_files, "OVIP_TESTS_PKG_BODY",
                               "eda_tests_body", MAX_CHUNK, search)

    # Outer wrapper: inline the small stuff, reference the chunks via `include.
    outer_parts = []
    outer_parts.append("// ===== eda_00_top.sv =====\n")
    outer_parts.append("// Auto-generated by tools/bundle_for_eda.py.\n\n")
    outer_parts.append('`include "uvm_macros.svh"\n\n')

    for f in [COMMON_SRC / "ovip_global_pkg.sv",
              MEM_SRC    / "ovip_mem_pkg.sv"]:
        # mem_pkg includes ovip_mem.sv; inline both
        text = read(f)
        # rewrite its internal `include "ovip_mem.sv"` to a direct inline
        def inline_local_include(match):
            inc = match.group(1)
            if inc in PASSTHRU:
                return match.group(0)
            p = resolve(inc, search)
            return f"// ----- inlined: {inc} -----\n{read(p)}\n// ----- end {inc} -----" if p else match.group(0)
        text = re.sub(r'`include\s*"([^"]+)"', inline_local_include, text)
        outer_parts.append(f"// ----- {f.name} -----\n{text}\n")

    # Top-level VIP includes (defines, macros, agent_if) come before the package.
    for f in [VIP_SRC / "ovip_axi_defines.sv",
              VIP_SRC / "ovip_axi_macros.sv",
              VIP_SRC / "ovip_axi_agent_if.sv"]:
        outer_parts.append(f"// ----- {f.name} -----\n{read(f)}\n")

    # ovip_axi_pkg wrapper: define guard, `include each VIP body chunk, undef.
    outer_parts.append("\npackage ovip_axi_pkg;\n")
    outer_parts.append("\timport uvm_pkg::*;\n")
    outer_parts.append("\timport ovip_global_pkg::*;\n")
    outer_parts.append("\timport ovip_mem_pkg::*;\n\n")
    outer_parts.append("\t`define OVIP_AXI_PKG_BODY\n")
    for name, _ in vip_chunks:
        outer_parts.append(f'\t`include "{name}"\n')
    outer_parts.append("\t`undef OVIP_AXI_PKG_BODY\n")
    outer_parts.append("endpackage : ovip_axi_pkg\n")

    # ovip_tests_pkg wrapper: same pattern, with the proper imports.
    outer_parts.append("\npackage ovip_tests_pkg;\n")
    outer_parts.append("\timport uvm_pkg::*;\n")
    outer_parts.append("\timport ovip_global_pkg::*;\n")
    outer_parts.append("\timport ovip_mem_pkg::*;\n")
    outer_parts.append("\timport ovip_axi_pkg::*;\n\n")
    outer_parts.append("\t`define OVIP_TESTS_PKG_BODY\n")
    for name, _ in tests_chunks:
        outer_parts.append(f'\t`include "{name}"\n')
    outer_parts.append("\t`undef OVIP_TESTS_PKG_BODY\n")
    outer_parts.append("endpackage : ovip_tests_pkg\n")

    # tb top
    outer_parts.append(f"\n// ----- tb.sv -----\n{read(TB_SRC / 'tb.sv')}\n")

    outer_text = "".join(outer_parts)
    (out_dir / "eda_00_top.sv").write_text(outer_text)

    # Write the chunk files.
    written = [("eda_00_top.sv", len(outer_text))]
    for name, text in vip_chunks + tests_chunks:
        (out_dir / name).write_text(text)
        written.append((name, len(text)))

    biggest_name, biggest_size = max(written, key=lambda x: x[1])
    print(f"Wrote {len(written)} files to {out_dir}")
    print(f"Largest file: {biggest_name} ({biggest_size:,} bytes)")
    if biggest_size > 100_000:
        print(f"WARNING: {biggest_name} exceeds EDA Playground's 100KB cap!", file=sys.stderr)
    else:
        print("All files are under EDA Playground's 100KB-per-file cap.")

    print("\n--- file list ---")
    for n, s in sorted(written):
        print(f"  {s:>7,}  {n}")


if __name__ == "__main__":
    main()
