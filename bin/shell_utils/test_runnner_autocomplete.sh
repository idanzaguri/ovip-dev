#!/bin/bash

_test_runner_completion() {
    local cur prev words cword
    # Initialize completion variables.
    # If _init_completion is available (from bash-completion), you can use:
    # _init_completion || return
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local repo_top
    repo_top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    
    # Define the available options.
    local opts="--block --test --simulator --top --dut --clean --pedant --rundir --rundir-suffix --files --seed --verbosity --uvm_test --uvm_max_quit --compile_only --run_only --gui --dump --dump-mem --codecov --sim_args --comp_args -h"

    # If the current word starts with a dash, complete options.
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    # Define verbosity levels when completing -verbosity
    if [[ "$prev" == "--verbosity" ]]; then
        COMPREPLY=( $(compgen -W "UVM_HIGH UVM_MEDIUM UVM_LOW UVM_NONE" -- "$cur") )
        return 0
    fi

    # Simulator choices when completing --simulator
    if [[ "$prev" == "--simulator" ]]; then
        COMPREPLY=( $(compgen -W "modelsim vcs" -- "$cur") )
        return 0
    fi

    # If the previous word was "--block", complete block names.
    if [[ "$prev" == "--block" ]]; then
        # Locate the git repository top.
        local verif_dir="$repo_top/verif"
        # If the "verif" directory exists, list its subdirectories.
        if [[ -d "$verif_dir" ]]; then
            local blocks
            # This command lists the names of directories under verif.
            blocks=$(find "$verif_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null)
            COMPREPLY=( $(compgen -W "$blocks" -- "$cur") )
        fi
        return 0
    fi

    # If the previous word was "--test", complete test names.
    if [[ "$prev" == "--test" ]]; then
        # First, find the block value given in the command line.
        local block=""
        local i
        for (( i=0; i < ${#COMP_WORDS[@]}; i++ )); do
            if [[ "${COMP_WORDS[i]}" == "--block" && $((i+1)) -lt ${#COMP_WORDS[@]} ]]; then
                block="${COMP_WORDS[i+1]}"
                break
            fi
        done

        # If no block is specified, there's nothing to complete.
        [[ -z "$block" ]] && return 0

        # Call your helper script (or function) that returns the tests for a block.
        local tests
        tests=$(python3 $repo_top/bin/shell_utils/get_tests.py "$block")
        COMPREPLY=( $(compgen -W "$tests" -- "$cur") )
        return 0
    fi

    # Fallback: complete available options.
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    return 0
}


complete -F _test_runner_completion test_runner

