import argparse
import os
from proj_utils import *
from log_utils import *


# ----------------------------------------------------------------------
# Log-scan patterns: shared between simulators where possible (UVM ones
# look the same on every UVM-1.2 simulator) and simulator-specific for
# the rest.
# ----------------------------------------------------------------------
UVM_SIM_PASSED = [r"--- UVM Report Summary ---"]
UVM_SIM_WARN   = [r"UVM_WARNING.* @"]
UVM_SIM_FAIL   = [r"UVM_ERROR.* @", r"UVM_FATAL.*@"]

# Modelsim/Questa
ms_comp_passed = [r"^End time:"]
ms_comp_warn   = [r"^\*\* Warning:"]
ms_comp_fail   = [r"^\*\* Error:"]
ms_comp_waive  = []

ms_sim_passed  = UVM_SIM_PASSED
ms_sim_warn    = UVM_SIM_WARN  + [r"^# \*\* Warning:"]
ms_sim_fail    = UVM_SIM_FAIL  + [r"^# \*\* Error:"]
ms_sim_waive   = [r"Warning: \(vopt-10587\)", r"Warning: \(vopt-13408\) Code coverage", r"Warning: \(vopt-10908\) Some"]

# VCS
vcs_comp_passed = [r"Chronologic VCS"]   # presence of the VCS banner is enough
vcs_comp_warn   = [r"^Warning-\["]
vcs_comp_fail   = [r"^Error-\[", r"^\s*Error:"]
vcs_comp_waive  = []

vcs_sim_passed  = UVM_SIM_PASSED
vcs_sim_warn    = UVM_SIM_WARN  + [r"^Warning-\["]
vcs_sim_fail    = UVM_SIM_FAIL  + [r"^Error-\[", r"\$fatal"]
vcs_sim_waive   = []

wa_root = None


def write_filelist(filelist_path, data):
    """Writes include directories, defines, and file paths to a filelist."""
    with open(filelist_path, "w") as f:
        for entry in data:
            f.write(entry + "\n")


def _resolve_simdir(args):
    if args.rundir:
        return args.rundir
    simdir = f'{wa_root}/sim/{args.block}/{args.test}_{args.seed}'
    if args.rundir_suffix:
        simdir += f'_{args.rundir_suffix}'
    return simdir


def _gather_attrs_and_filelist(args, simdir):
    """Run jinja substitution, parse attributes, write the filelist (shared
    between simulators -- +define+/+incdir+ syntax is the same for both)."""
    jinja2_variables = {
        "TOOL": "vsim" if args.simulator == "modelsim" else "vcs",
        "WA_ROOT": wa_root,
        "TOP_BLOCK": args.block,
        **os.environ,
    }
    attributes_to_parse = ["include_dirs", "defines", "files", "comp_args", "sim_args"]
    attributes = parse_attributes(args.block, "verif", attributes_to_parse, jinja2_variables)

    data = []
    if args.comp_args:
        data.extend([w for sub in args.comp_args for item in sub for w in item.split()])
    data.extend(attributes["comp_args"])
    data.extend([f"+define+{d}" for d in attributes["defines"]])
    data.extend([f"+incdir+{d}" for d in attributes["include_dirs"]])
    data.extend(attributes["files"])
    if args.files:
        data.extend([w for sub in args.files for item in sub for w in item.split()])
    write_filelist(f"{simdir}/comp_filelist.f", data)

    sim_args = []
    if args.sim_args:
        sim_args.extend([w for sub in args.sim_args for item in sub for w in item.split()])
    sim_args.extend(attributes["sim_args"])
    return " ".join(sim_args)


# ----------------------------------------------------------------------
# Modelsim / Questa path
# ----------------------------------------------------------------------
def run_modelsim(args, simdir, sim_args):
    try:
        with open(f'{simdir}/sim.do', 'w') as f:
            if args.dump_mem:
                f.write(f"log -r {args.dut}/* -nofilter {{Memory}};\n")
            elif args.dump:
                f.write(f"log -r {args.dut}/*;\n")
            f.write("run -all;\n")
            if args.codecov:
                f.write(f"coverage save -testname {args.test}_{args.seed} -instance {args.dut} coverage.ucdb;\n")
            f.write("quit;\n")
    except Exception as e:
        print_message("error", f"An error occurred: {e}")
        exit(1)

    vlib_cmd = "vlib -type flat sv_tb_work"
    vlog_cmd = "vlog -lint=full -work sv_tb_work +acc=nprt -l comp.log -mfcu -f comp_filelist.f"
    vsim_cmd = f"vsim -c -onfinish stop -work sv_tb_work -l run.log -do sim.do -sv_seed {args.seed} {args.top} {sim_args}"

    if args.uvm_test:
        vsim_cmd += f" +UVM_TESTNAME={args.uvm_test} +UVM_MAX_QUIT_COUNT={args.uvm_max_quit} +UVM_VERBOSITY={args.verbosity}"

    if args.dump or args.dump_mem:
        vsim_cmd += " -wlf waves.wlf -voptargs=+acc -debugdb"
    else:
        # FIXME: a simulator optimization bug introduces race conditions (e.g. ovip_axi_4lite_test
        # fails). Disabling optimization with +acc works around it until the root cause is fixed.
        vsim_cmd += " -voptargs=+acc"

    if args.codecov:
        vlog_cmd += " -cover bcefsx"
        vsim_cmd += " -coverage"

    do_comp = not args.run_only
    do_sim  = not args.compile_only

    if do_comp:
        r = run_command(vlib_cmd, simdir)
        if r:
            print_message('error', f"VLIB Failed {r}")
            exit(1)
        r = run_command(vlog_cmd, simdir)
        status = parse_log(f"{simdir}/comp.log", ms_comp_passed, ms_comp_warn, ms_comp_fail, ms_comp_waive, False, True)
        if r or status in ("FAILED", "UNKNOWN") or (status == "PASSED_WARN" and args.pedant):
            print_message('error', "Compilation Failed")
            print_message('error', f"LOG:  {simdir}/comp.log")
            exit(1)

    if do_sim:
        r = run_command(vsim_cmd, simdir)
        if r:
            print_message('error', f"Simulation Failed {r}")
            exit(1)
        status = parse_log(f"{simdir}/run.log", ms_sim_passed, ms_sim_warn, ms_sim_fail, ms_sim_waive, True, True)
        print("---")
        print(f"LOG:  {simdir}/run.log")
        if args.dump or args.dump_mem:
            print(f"DUMP: {simdir}/waves.wlf")
        if r or status in ("FAILED", "UNKNOWN"):
            exit(1)
        if status == "PASSED_WARN":
            exit(1 if args.pedant else 2)


# ----------------------------------------------------------------------
# VCS path (best-effort -- the user does not have VCS available locally, so
# this has not been runtime-validated. Keep it close to the documented VCS
# command shape so the eventual smoke test is small.)
# ----------------------------------------------------------------------
def run_vcs(args, simdir, sim_args):
    # The Modelsim filelist already uses +define+/+incdir+ which VCS accepts
    # natively; the file paths in the list are plain SV sources which vcs
    # consumes via -f.

    comp_cmd_parts = [
        "vcs",
        "-full64",
        "-sverilog",
        "-ntb_opts uvm-1.2",
        "-timescale=1ns/1ps",
        "-l comp.log",
        f"-top {args.top}",
        "-f comp_filelist.f",
        "-o simv",
    ]
    if args.dump or args.dump_mem:
        comp_cmd_parts.append("-debug_access+all")
    else:
        # -debug_access+pp gives enough visibility for UVM hierarchical access
        # without forcing the larger debug DB. Drop if it bloats compile time.
        comp_cmd_parts.append("-debug_access+pp")
    if args.codecov:
        comp_cmd_parts.append("-cm line+cond+fsm+tgl+branch")
    comp_cmd = " ".join(comp_cmd_parts)

    sim_cmd_parts = [
        "./simv",
        "-l run.log",
        f"+ntb_random_seed={args.seed}",
    ]
    if args.uvm_test:
        sim_cmd_parts += [
            f"+UVM_TESTNAME={args.uvm_test}",
            f"+UVM_MAX_QUIT_COUNT={args.uvm_max_quit}",
            f"+UVM_VERBOSITY={args.verbosity}",
        ]
    if args.dump or args.dump_mem:
        dump_do = f"{simdir}/dump.do"
        with open(dump_do, "w") as f:
            f.write("set fid [dump -file waves.vpd -type VPD]\n")
            # -depth 0 captures the full hierarchy; -aggregates adds memories/arrays.
            agg = " -aggregates" if args.dump_mem else ""
            f.write(f"dump -add {args.dut} -depth 0 -fid $fid{agg}\n")
            f.write("run\n")
            f.write("quit\n")
        sim_cmd_parts += ["-ucli", "-do dump.do"]
    if args.codecov:
        sim_cmd_parts.append("-cm line+cond+fsm+tgl+branch")
        sim_cmd_parts.append(f"-cm_name {args.test}_{args.seed}")
    if sim_args:
        sim_cmd_parts.append(sim_args)
    sim_cmd = " ".join(sim_cmd_parts)

    do_comp = not args.run_only
    do_sim  = not args.compile_only

    if do_comp:
        r = run_command(comp_cmd, simdir)
        status = parse_log(f"{simdir}/comp.log", vcs_comp_passed, vcs_comp_warn, vcs_comp_fail, vcs_comp_waive, False, True)
        if r or status in ("FAILED", "UNKNOWN") or (status == "PASSED_WARN" and args.pedant):
            print_message('error', "Compilation Failed")
            print_message('error', f"LOG:  {simdir}/comp.log")
            exit(1)

    if do_sim:
        r = run_command(sim_cmd, simdir)
        if r:
            print_message('error', f"Simulation Failed {r}")
            exit(1)
        status = parse_log(f"{simdir}/run.log", vcs_sim_passed, vcs_sim_warn, vcs_sim_fail, vcs_sim_waive, True, True)
        print("---")
        print(f"LOG:  {simdir}/run.log")
        if args.dump or args.dump_mem:
            print(f"DUMP: {simdir}/waves.vpd")
        if r or status in ("FAILED", "UNKNOWN"):
            exit(1)
        if status == "PASSED_WARN":
            exit(1 if args.pedant else 2)


def generate_sim_command(args):
    simdir = _resolve_simdir(args)
    if args.clean:
        shutil.rmtree(simdir, ignore_errors=True)
    os.makedirs(simdir, exist_ok=True)

    sim_args = _gather_attrs_and_filelist(args, simdir)

    if args.simulator == "vcs":
        run_vcs(args, simdir, sim_args)
    else:
        run_modelsim(args, simdir, sim_args)


def parse_test_args(block, test):
    """Retrieve compilation and simulation arguments for a specific test."""
    block_dir = f"{wa_root}/verif/{block}"
    tests_config = f"{block_dir}/lib/tests.yaml"
    print_message("info", f"Parsing Tests config YAML - {tests_config}")
    content = load_yaml(tests_config)

    test_context = next((t for t in content.get('tests', []) if t['name'] == test), None)
    if not test_context:
        print_message("error", f"Test '{test}' not found in {tests_config}")
        exit(1)

    comp_context = next((c for c in content.get('compilations', []) if c['name'] == test_context['comp']), None)
    if not comp_context:
        print_message("error", f"Compilation '{test_context['comp']}' not found for test '{test}'")
        exit(1)

    additional_args = []

    attributes = ["files", "args"]
    for attrib in attributes:
        if attrib not in comp_context or comp_context[attrib] is None:
            continue
        value = comp_context[attrib]
        if isinstance(value, str):
            value = [value]
        assert isinstance(value, list), f"{attrib} must be a list"
        if attrib in ["files"]:
            value = [make_path_abs(f, block_dir) for f in value]
            value = ["--files "+' '.join(value)]
        additional_args += value

    if "args" in test_context and test_context["args"] is not None:
        value = test_context["args"]
        if isinstance(value, str):
            value = [value]
        assert isinstance(value, list), f"{attrib} must be a list"
        additional_args += value

    return [word for item in additional_args for word in item.split()]



def main():
    global wa_root
    wa_root = get_git_root()
    if not wa_root:
        print_message("error","You are not inside valid workarea.")
        exit(1)

    VERBOSITY_LEVELS = ['UVM_HIGH', 'UVM_MEDIUM', 'UVM_LOW', 'UVM_NONE']
    parser = argparse.ArgumentParser(description="UVM Test Runner Wrapper (Modelsim/Questa or VCS)")

    parser.add_argument("-b",'--block', type=str, help="name of design or verif block", required=True)
    parser.add_argument('-t', '--test', type=str, help="test name (as defined in tests,.yaml)", required=True)
    parser.add_argument('--simulator', type=str, choices=['modelsim', 'vcs'], default='modelsim',
                        help="Which simulator to use (default: modelsim). The VCS path is best-effort and may need tuning for your install.")
    parser.add_argument('--top', type=str, default='tb', help="Set top module name (default: tb)")
    parser.add_argument('--dut', type=str, help="Set top module name (default: tb)")
    parser.add_argument("--clean", action="store_true", help="clean run directory")
    parser.add_argument("--pedant", action="store_true", help="Stop run when there are warnings")
    parser.add_argument("--rundir", type=str, help="Set user-defined rundir")
    parser.add_argument("--rundir-suffix", dest="rundir_suffix", type=str, help="Append a suffix to the auto-generated rundir (ignored if --rundir is set). Useful for running the same test+seed in multiple directories.")
    parser.add_argument("--files", action="append", nargs="*", help="Command arguments to pass to compilation process")

    parser.add_argument('-s', '--seed', type=int, default=0, help="Set the seed (default: 0)")
    parser.add_argument('--verbosity', type=str, choices=VERBOSITY_LEVELS, default='UVM_LOW', help="Set verbosity level (default: UVM_LOW)")
    parser.add_argument('--uvm_test', type=str, help="test name for UVM_TESTNAME")
    parser.add_argument('--uvm_max_quit', type=int, default=3, help="Set value for UVM_MAX_QUIT_COUNT")
    parser.add_argument("--compile-only", action="store_true", help="Only compile without running")
    parser.add_argument("--run-only", action="store_true", help="Only run without compiling")
    parser.add_argument("--gui", action="store_true", help="Run ModelSim in GUI mode")
    parser.add_argument("--dump", action="store_true", help="Collect dump file")
    parser.add_argument("--dump-mem", action="store_true", help="Collect dump file including memories")
    parser.add_argument("--codecov", action="store_true", help="Collect code coverage")
    parser.add_argument("--sim_args", action="append", nargs="*", help="Command arguments to pass to simulation process")
    parser.add_argument("--comp_args", action="append", nargs="*", help="Command arguments to pass to compilation process")

    original_args = sys.argv[1:]
    args = parser.parse_args()

    if args.test:
        additional_args = parse_test_args(args.block, args.test)
        try:
            args = parser.parse_args(original_args + additional_args)
        except SystemExit:
            print_message("error",f"Additional arguments from tests.yaml failed. check error message above")
            exit(1)

    if args.dut is None:
        args.dut = args.top

    generate_sim_command(args)

if __name__ == "__main__":
    main()
