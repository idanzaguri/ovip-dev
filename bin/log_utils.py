import os
import re
import sys
from proj_utils import *


def print_test_status(status):
    if status in ["PASSED","PASSED_WARN"]:
        color = "\033[92m"
        if status == "PASSED_WARN":
            color = "\033[93m"
        print(f"{color} ___ _  __ ___    _       __  __  _  _  \033[0m")
        print(f"{color}  | |_ (_   |    |_) /\\  (_  (_  |_ | \\ \033[0m")
        print(f"{color}  | |_ __)  |    |  /--\\ __) __) |_ |_/ \033[0m")
    else:
        color = "\033[91m"
        print(f"{color} ___ _  __ ___    _     ___     _  _    \033[0m")
        print(f"{color}  | |_ (_   |    |_ /\\   |  |  |_ | \\   \033[0m")
        print(f"{color}  | |_ __)  |    | /--\\ _|_ |_ |_ |_/   \033[0m")

def parse_log(log_file_path,passed_patterns=[],warning_patterns=[],failed_patterns=[], waiver_patterns=[], print_banner=False, print_matches=False):
    # Default status so a missing/unreadable log file still returns cleanly.
    status = "UNKNOWN"
    try:
        with open(log_file_path, 'r') as log_file:
            lines = log_file.readlines()

        # Variables to track test status and errors
        errors = []
        warnings = []
        # Iterate through lines to check for passed and failed patterns
        for line in lines:
            # Check for waiver patterns
            if any(re.search(pattern, line) for pattern in waiver_patterns):
                continue
            # Check for failed patterns
            if any(re.search(pattern, line) for pattern in failed_patterns):
                status = "FAILED"
                errors.append(line.strip())
            # Check for warning patterns
            if any(re.search(pattern, line) for pattern in warning_patterns):
                print(f"{line}")
                warnings.append(line.strip())
            # Check for passed patterns (only if status is still UNKNOWN)
            if status == "UNKNOWN" and all(re.search(pattern, line) for pattern in passed_patterns):
                status = "PASSED"

        if status == "PASSED" and warnings:
                status = "PASSED_WARN"

        if print_banner:
            print_test_status(status)
        
        if print_matches:
            if status == "FAILED":
                print("\nFirst Error(s) Found:")
                for error in errors:
                    print_message('error', error)
            elif status == "PASSED_WARN":
                print("\nFirst Warning(s) Found:")
                for warning in warnings:
                    print_message('error',warning)
    except Exception as e:
        print_message("error",f"An error occurred while processing the log file: {e}")
   
    return status



def replace_lines_in_pattern_file(pattern_file_path, new_file_path,  identifier, new_lines):
    with open(pattern_file_path, "r") as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        if identifier in line:
            lines[i:i+1] = [new_line + "\n" for new_line in new_lines]
            break  # Stop after the first match

    with open(new_file_path, "w") as f:
        f.writelines(lines)

