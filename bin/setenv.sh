#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Project environment for ovip-dev.
#
# Sourced automatically by bin/runners/test_runner.py before compile/sim, and
# safe to source by hand too:
#     source bin/setenv.sh
#
# OVIP_ROOT defaults to this repo (ovip-dev *is* the OVIP source tree, so the
# filelist's $OVIP_ROOT expansion lands here). To point at a different checkout
# anyway, drop an override in bin/setenv.local.sh (gitignored, per-developer):
#     echo 'export OVIP_ROOT=/other/path/to/ovip' > bin/setenv.local.sh
# -----------------------------------------------------------------------------

# Per-developer overrides (gitignored), sourced first so anything they export
# wins over the defaults below.
_setenv_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_setenv_dir/setenv.local.sh" ] && source "$_setenv_dir/setenv.local.sh"

# Default OVIP_ROOT to this repo's root. The OVIP filelists (ovip_axi.f etc.)
# expand $OVIP_ROOT at compile time, so this must be a real environment variable.
: "${OVIP_ROOT:=$(cd "$_setenv_dir/.." && pwd)}"
[ -f "$OVIP_ROOT/verif/ovip_axi/ovip_axi.f" ] || \
    echo "setenv.sh: WARNING: OVIP_ROOT=$OVIP_ROOT has no verif/ovip_axi/ovip_axi.f -- wrong path?" >&2
export OVIP_ROOT

# Verilator (test_runner --simulator verilator). Nothing is set here: the values
# are per machine, so they go in bin/setenv.local.sh (gitignored).
#   verilator         taken from PATH; put the build you want first on PATH.
#                     ovip_axi needs a build newer than 5.052 (parameterized
#                     class with a virtual-interface type parameter). Do not
#                     set VERILATOR_BIN: that is Verilator's own variable, the
#                     path of its verilator_bin program.
#   VERILATOR_SOLVER  SMT solver command for randomize(), e.g. "z3 --in" or
#                     "yices-smt2 --incremental"; without one randomize() returns 0.
#   UVM_HOME          a UVM 1.2 source tree; the runner falls back to the one
#                     next to vsim when unset.

unset _setenv_dir
