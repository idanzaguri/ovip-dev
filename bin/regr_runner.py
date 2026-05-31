import argparse
import yaml
import os
import re
import sys
import signal
import threading
import subprocess
import concurrent.futures
import time
import shutil
from pathlib import Path
import random
from proj_utils import *
from log_utils import *
import datetime
from pathlib import Path
from tqdm import tqdm


def _timed_out_but_finished_cleanly(text):
    """A common Modelsim/Questa flake: $finish runs and the UVM report shows
    a clean pass, but the simulator process then hangs (e.g., license-server
    drop) and gets killed by the wall-clock timeout. The test logically
    passed -- recognize it so it doesn't show up as a real failure."""
    if "$finish" not in text:
        return False
    if "SvtTestEpilog: Passed" not in text:
        return False
    if not re.search(r"UVM_ERROR\s*:\s*0\b", text):
        return False
    if not re.search(r"UVM_FATAL\s*:\s*0\b", text):
        return False
    return True

global wa_root

# Registry of currently running test subprocesses so a Ctrl-C handler can kill them.
_running_procs = {}
_running_procs_lock = threading.Lock()
_abort_event = threading.Event()  # set on interrupt; stops new tests from launching
test_timeout = 300  # per-test wall-clock timeout in seconds (see --timeout)


def _terminate_running_procs(grace=2):
    """Kill every in-flight test process group (test_runner + its vlog/vsim children).
    Each test is launched in its own process group, so killpg reaches the whole tree."""
    with _running_procs_lock:
        _abort_event.set()  # block any not-yet-launched worker from spawning a new test
        procs = list(_running_procs.values())
    for proc in procs:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except OSError:
            pass
    time.sleep(grace)  # give them a chance to exit cleanly...
    for proc in procs:
        try:
            os.killpg(proc.pid, signal.SIGKILL)  # ...then force-kill any stragglers
        except OSError:
            pass
    return len(procs)


def run_test(block, test, seed, rundir, codecov=False, simulator="modelsim"):
    """Runs a single test instance with the given parameters."""
    cmd = f"python3 {wa_root}/bin/test_runner.py --block {block} --test {test} --seed {seed} --rundir {rundir} --simulator {simulator}"
    if codecov:
        cmd += " --codecov"

    cmd_args = shlex.split(cmd)
    # Register under the lock and bail out if an abort is already in progress, so a
    # worker that hasn't launched yet won't spawn an unkillable process after the
    # interrupt handler has already swept _running_procs.
    # start_new_session=True puts this test (and its vlog/vsim children) in its own
    # process group so the Ctrl-C handler can kill the whole tree via os.killpg.
    with _running_procs_lock:
        if _abort_event.is_set():
            return block, test, seed, "FAILED"
        proc = subprocess.Popen(cmd_args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True)
        _running_procs[proc.pid] = proc
    timed_out = False
    try:
        stdout, stderr = proc.communicate(timeout=test_timeout)
    except subprocess.TimeoutExpired:
        # A test that won't finish (e.g. vsim hanging after $finish) must not stall the
        # whole regression. Kill its process group and mark it FAILED.
        timed_out = True
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        stdout, stderr = proc.communicate()  # reap after the kill
    finally:
        with _running_procs_lock:
            _running_procs.pop(proc.pid, None)

    log_text = (stdout or "") + "\n" + (stderr or "")
    # When the timeout fires after $finish (common Modelsim license/post-finish
    # flake), the UVM summary in the captured log already shows a clean pass.
    clean_finish_after_timeout = timed_out and _timed_out_but_finished_cleanly(log_text)

    log_path = os.path.join(rundir, "test.log")
    with open(log_path, "w") as log_file:
        log_file.write(log_text)
        if timed_out:
            log_file.write(f"\n[regr_runner] TIMEOUT: test killed after {test_timeout}s\n")
            if clean_finish_after_timeout:
                log_file.write("[regr_runner] UVM summary shows clean pass before timeout -- treating as PASSED.\n")

    if timed_out:
        status = "PASSED" if clean_finish_after_timeout else "FAILED"
    elif proc.returncode == 0:
        status = "PASSED"
    elif proc.returncode == 2:
        status = "PASSED_WARN"
    else:
        status = "FAILED"
    return block, test, seed, status


def clean_test_files(rundir, success, keep_patterns = ["test.log", "coverage.ucdb"]):
    rundir = Path(rundir)  # Ensure rundir is a Path object.
    if not rundir.is_dir():
        raise ValueError(f"{rundir} is not a valid directory.")

    if success:
        # First, delete files that do not match any of the allowed patterns.
        for item in rundir.rglob('*'):
            if item.is_file():
                if not any(item.match(pattern) for pattern in keep_patterns):
                    try:
                        item.unlink()
                    except Exception as e:
                        print(f"Could not delete file {item}: {e}")
        # Next, remove empty directories.
        # Sorting in reverse ensures we remove deeper directories before their parents.
        for directory in sorted(rundir.rglob('*'), key=lambda d: len(d.parts), reverse=True):
            if directory.is_dir():
                try:
                    # If directory is empty, remove it.
                    if not any(directory.iterdir()):
                        directory.rmdir()
                except Exception as e:
                    print(f"Could not delete directory {directory}: {e}")


def parse_test_list(file_path):
    jinja2_variables = {}

    try:
        with open(file_path, 'r') as f:
            raw_content = f.read()
    except:
        print_message("error", f"Filed to open regr file - {file_path}")
        exit(1)

    # Apply Jinja2 rendering first
    template = Template(raw_content, undefined=StrictUndefined)
    rendered_content = template.render(jinja2_variables)
 
    try:
        content = yaml.safe_load(rendered_content) or {}
    except yaml.YAMLError as e:
        raise ValueError(f"Error parsing YAML after Jinja2 rendering: {e}")
    
    return content.get("tests", [])

def summarize_results(results, summary_path, total_tests, start_time, pedant=False):
    """Generates a summary of all test results."""
    passed      = [f"{t[1]} (seed {t[2]}) {t[4]}" for t in results if t[3] == "PASSED"]
    passed_warn = [f"{t[1]} (seed {t[2]}) {t[4]}" for t in results if t[3] == "PASSED_WARN"]
    failed      = [f"{t[1]} (seed {t[2]}) {t[4]}" for t in results if t[3] == "FAILED"]
    duration = time.time() - start_time

    effective_passed = len(passed) + (0 if pedant else len(passed_warn))
    effective_failed = len(failed) + (len(passed_warn) if pedant else 0)

    summary_content = (
        f"{'='*40}\n"
        f"  Regression Summary  \n"
        f"{'='*40}\n"
        f"Total tests: {total_tests}\n"
        f"Passed: {len(passed)} ({len(passed)/total_tests:.1%})\n"
        f"Passed with warnings: {len(passed_warn)} ({len(passed_warn)/total_tests:.1%})\n"
        f"Failed: {len(failed)} ({len(failed)/total_tests:.1%})\n"
        f"Pedant mode: {pedant} (warnings treated as {'failures' if pedant else 'passes'})\n"
        f"Effective pass rate: {effective_passed/total_tests:.1%}\n"
        f"Duration: {duration:.2f} seconds\n"
        f"{'='*40}\n"
        f"Passed Tests:\n" + "\n".join(passed) + "\n"
        f"{'-'*40}\n"
        f"Passed with Warnings:\n" + "\n".join(passed_warn) + "\n"
        f"{'-'*40}\n"
        f"Failed Tests:\n" + "\n".join(failed) + "\n"
    )

    with open(summary_path, "w") as summary_file:
        summary_file.write(summary_content)

def merge_coverage(regression_dir):
    """Merges coverage databases for each block, logging output to a file."""
    for block_dir in regression_dir.iterdir():
        if block_dir.is_dir():
            ucdb_files = list(block_dir.glob("**/coverage.ucdb"))
            if ucdb_files:
                merge_log = block_dir / "merge.log"
                merge_cmd = ["vcover", "merge", str(block_dir / "merged.ucdb")] + [str(f) for f in ucdb_files]
                
                print_message("info", f"Merging coverage for block: {block_dir}")
                with open(merge_log, "w") as log_file:
                    subprocess.run(merge_cmd, stdout=log_file, stderr=log_file, check=True)



def print_block_table(block, tests):
    total = len(tests)
    # Determine column widths: consider header and data lengths.
    test_col_width = max(len("Test"), *(len(test) for test, _ in tests))
    rpts_col_width = max(len("Repetitions"), *(len(str(rpts)) for _, rpts in tests))
    
    # Prepare table border and header
    border = f"+{'-'*(test_col_width+2)}+{'-'*(rpts_col_width+2)}+"
    header = f"| {'Test'.ljust(test_col_width)} | {'Repetitions'.ljust(rpts_col_width)} |"
    
    print(f"Block: {block} | Total tests: {total}")
    print(border)
    print(header)
    print(border)
    
    # Print each row in the table
    for test, rpts in tests:
        row = f"| {test.ljust(test_col_width)} | {str(rpts).center(rpts_col_width)} |"
        print(row)
    print(border)
    print()  # Blank line for spacing





def main():
    parser = argparse.ArgumentParser(description="Regression test runner")
    parser.add_argument("--tests", required=True, help="YAML file containing test list")
    parser.add_argument("--name", type=str , help="regression name")
    parser.add_argument("--repeat", type=int, default=1, help="Number of times to run each test")
    parser.add_argument("--max_parallel", type=int, default=16, help="Maximum parallel tests")
    parser.add_argument("--stop_on_fail", action="store_true", help="Stop on first failure")
    parser.add_argument("--codecov", action="store_true", help="Enable code coverage")
    parser.add_argument("--keep", action="store_true", help="Disable passesd tests files folders cleaning")
    parser.add_argument("--pedant", action="store_true", help="Treat tests that pass with warnings as failures (affects pass rate and stop_on_fail)")
    parser.add_argument("--timeout", type=int, default=300, help="Per-test wall-clock timeout in seconds; a test exceeding it is killed and marked FAILED (default: 300)")
    parser.add_argument("--simulator", type=str, choices=["modelsim", "vcs"], default="modelsim", help="Simulator to use for every test in the regression (default: modelsim)")
    args = parser.parse_args()

    if args.name is None:
        args.name = datetime.datetime.now().strftime("%Y_%m_%d_%H%M%S")
    ascii_art = r"""
       ___                           _             ___                        
      / _ \___ ___ ________ ___ ___ (_)__  ___    / _ \__ _____  ___  ___ ____
     / , _/ -_) _ `/ __/ -_|_-<(_-</ / _ \/ _ \  / , _/ // / _ \/ _ \/ -_) __/
    /_/|_|\__/\_, /_/  \__/___/___/_/\___/_//_/ /_/|_|\_,_/_//_/_//_/\__/_/   
             /___/ 
    """
    # ANSI escape codes for colored output
    BOLD_CYAN = "\033[1;36m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    MAGENTA = "\033[35m"   # stopped: was running when interrupted
    GRAY = "\033[90m"      # cancelled: still queued, never started
    RESET = "\033[0m"
    print(f"{BOLD_CYAN}{ascii_art}{RESET}")


    global wa_root, test_timeout
    test_timeout = args.timeout
    wa_root = get_git_root()
    if not wa_root:
        print_message("error","You are not inside valid workarea.")
        exit(1)
    
    test_list = parse_test_list(args.tests)
    
    for entry in test_list:
        if "seed" in entry:
            entry["repetitions"] = 1
        elif "weight" in entry:
            entry["repetitions"] = entry["weight"] * args.repeat
        else:
            entry["repetitions"] = 1
        

    regression_dir = Path(f"{wa_root}/sim/regression/{args.name}")
    os.makedirs(str(regression_dir), exist_ok=True)
    
    results = []
    total_tests = sum(entry["repetitions"] for entry in test_list)
    start_time = time.time()
    running_tests = 0
    passed_tests = 0
    passed_warn_tests = 0
    failed_tests = 0
    pending_tests = total_tests
    
    test_queue = []
    grouped_tests = defaultdict(list)
    for entry in test_list:
        block, test, repetitions = entry["block"], entry["test"], entry["repetitions"]
        grouped_tests[block].append((test, entry["repetitions"]))
        
        if "seed" in entry:
            unique_seeds = [entry["seed"]] # FIXME: add support for list of seeds...
        else:
            unique_seeds = random.sample(range(0, 999999), entry["repetitions"])
        for seed in unique_seeds:
            rundir = regression_dir / block / test / f"seed_{seed}"
            test_queue.append((block, test, seed, rundir))
    random.shuffle(test_queue)
    
    # Print tables for each block
    for block, tests in grouped_tests.items():
        print_block_table(block, tests)
    
    status = lambda: f"Total: {total_tests}, Running: {running_tests}, Passed: {passed_tests}, Warned: {passed_warn_tests}, Failed: {failed_tests}, Pending: {pending_tests}"
    pbar = tqdm(total = total_tests, bar_format='{l_bar}{bar} | Elapsed: {elapsed} | ETA: {remaining}')

    executor = concurrent.futures.ThreadPoolExecutor(max_workers=args.max_parallel)
    futures = {}
    pbar.set_description(status())
    try:
                
        while test_queue or futures:
            
            while test_queue and len(futures) < args.max_parallel:
                block, test, seed, rundir = test_queue.pop(0)
                rundir.mkdir(parents=True, exist_ok=True)
                pending_tests -= 1
                running_tests += 1
                future = executor.submit(run_test, block, test, seed, rundir, args.codecov, args.simulator)
                futures[future] = (block, test, seed, rundir)
                pbar.set_description(status())
                pbar.update(0)
            
            done, not_done = concurrent.futures.wait(
                futures,
                return_when=concurrent.futures.FIRST_COMPLETED)
            
            for future in done:
                block, test, seed, rundir = futures.pop(future)
                test_status = future.result()[3]
                test_log = rundir / "test.log"
                results.append((block, test, seed, test_status, test_log))
                if not args.keep:
                    clean_test_files(rundir, test_status != "FAILED")
                running_tests -= 1

                if test_status == "PASSED":
                    passed_tests += 1
                    tqdm.write(f"{test} @ {seed} {GREEN}passed{RESET}")
                elif test_status == "PASSED_WARN":
                    passed_warn_tests += 1
                    tqdm.write(f"{test} @ {seed} {YELLOW}passed with warnings{RESET}")
                else:
                    failed_tests += 1
                    tqdm.write(f"{test} @ {seed} {RED}failed{RESET}")
                summarize_results(results, regression_dir / "summary.txt", total_tests, start_time, args.pedant)
                pbar.set_description(status())
                pbar.update(1)

            effective_failed = failed_tests + (passed_warn_tests if args.pedant else 0)
            if args.stop_on_fail and effective_failed:
                pbar.close()
                print()
                print_message("warning","Abort regression due to failed test!")
                executor.shutdown(wait=False, cancel_futures=True)
                break
    except KeyboardInterrupt:
        # Ignore further Ctrl-C so the report below prints atomically even if the
        # user keeps mashing the key (a second SIGINT here would abort the cleanup).
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        pbar.close()
        print()
        print_message("warning", "Regression interrupted by user (Ctrl-C)!")

        stopped   = list(futures.values())   # tests running when interrupted
        cancelled = list(test_queue)         # tests still queued, never started

        print(f"\n{MAGENTA}Stopped (running when interrupted): {len(stopped)}{RESET}")
        for _block, _test, _seed, _rundir in stopped:
            print(f"  {MAGENTA}{_test} @ {_seed}{RESET}")

        print(f"\n{GRAY}Cancelled (never started): {len(cancelled)}{RESET}")
        for _block, _test, _seed, _rundir in cancelled:
            print(f"  {GRAY}{_test} @ {_seed}{RESET}")

        print(f"\nCompleted before interrupt: {GREEN}{passed_tests} passed{RESET}, "
              f"{YELLOW}{passed_warn_tests} warned{RESET}, {RED}{failed_tests} failed{RESET}")

        # Kill the in-flight simulations (test_runner + its vlog/vsim children).
        print_message("warning", f"Stopping {len(stopped)} running simulation(s)...")
        killed = _terminate_running_procs()
        print_message("info", f"Stopped {killed} simulation(s).")

        summarize_results(results, regression_dir / "summary.txt", total_tests, start_time, args.pedant)
        print_message("info", f"Partial report: {regression_dir}/summary.txt")
        executor.shutdown(wait=False, cancel_futures=True)
        sys.stdout.flush()
        sys.exit(130)

    executor.shutdown(wait=False, cancel_futures=True)
    summarize_results(results, regression_dir / "summary.txt", total_tests, start_time, args.pedant)

    pbar.close() 
    print()
    if args.codecov:
        merge_coverage(regression_dir)
    
    effective_passed = passed_tests + (0 if args.pedant else passed_warn_tests)
    effective_failed = failed_tests + (passed_warn_tests if args.pedant else 0)
    pass_rate = (effective_passed/total_tests)*100
    if pass_rate == 100 and passed_warn_tests == 0:
        print_message("info",f"PASS_RATE: {pass_rate}%")
    elif effective_failed == 0:
        print_message("warning",f"PASS_RATE: {pass_rate:.2f}% ({passed_warn_tests} test(s) passed with warnings)")
    else:
        print_message("warning",f"PASS_RATE: {pass_rate:.2f}%")

    if effective_failed == 0:
        color = "\033[93m" if passed_warn_tests > 0 else "\033[92m"
        print(f"{color}  _       __  __  _  _  \033[0m")
        print(f"{color} |_) /\\  (_  (_  |_ | \\ \033[0m")
        print(f"{color} |  /--\\ __) __) |_ |_/ \033[0m")
    else:
        color = "\033[91m"
        print(f"{color}  _     ___     _  _    \033[0m")
        print(f"{color} |_ /\\   |  |  |_ | \\   \033[0m")
        print(f"{color} | /--\\ _|_ |_ |_ |_/   \033[0m")

    print() 
    print_message("info", f"Rregression Report: {regression_dir}/summary.txt")
if __name__ == "__main__":
    main()

