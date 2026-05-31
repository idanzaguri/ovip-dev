import shutil
import shlex
import re
import signal
import subprocess
from collections import defaultdict
import sys
import os
import yaml
from jinja2 import Template, StrictUndefined



def get_git_root():
    try:
        # Run the git command to get the root of the repository
        git_root = subprocess.check_output(
            ['git', 'rev-parse', '--show-toplevel'],
            stderr=subprocess.STDOUT
        ).strip().decode('utf-8')
        return git_root
    except subprocess.CalledProcessError:
        # If the command fails, you're not inside a Git repository
        return None

def run_command(command, working_dir=None):
    """ Run a terminal command while forwarding Ctrl+C to the subprocess."""
    try:
        cwd = os.path.abspath(working_dir) if working_dir else None
        process = subprocess.Popen(shlex.split(command), cwd=cwd,
                                   stdout=sys.stdout, stderr=sys.stderr, stdin=sys.stdin)
        process.wait()
        return process.returncode
    except KeyboardInterrupt:
        process.send_signal(signal.SIGINT)  # Forward Ctrl+C
        process.wait()
        return process.returncode
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

def print_message(level, message):
    """Print messages with different levels (Error, Warning, Info, Debug)."""
    colors = {
        "error": "\033[91m",  # Red
        "warning": "\033[93m",  # Yellow
        "debug": "\033[96m",  # Yellow
        "info": "\033[92m",  # Green
        "reset": "\033[0m"  # Reset
    }
    print(f"{colors.get(level, colors['reset'])}[{level.upper()}] {message}{colors['reset']}")
    #print("\n❌ ERROR")


def make_path_abs(path, current_dir):
    if path.startswith('/'):
        print_message("warning", f"Using absolute path {path}")
        return path

    wa_root = get_git_root()
    block_path = os.path.join(current_dir, path)
    top_path = os.path.join(f"{wa_root}", path)
    found_paths = [p for p in [block_path, top_path] if os.path.exists(p)]

    if len(found_paths) > 1:
        print_message("error", f"File '{path}' found in multiple locations: {found_paths}")
        exit(1)
    if not found_paths:
        print_message("error", f"File '{path}' not found in block or top-level directory.")
        exit(1)
    return os.path.abspath(found_paths[0])



def load_yaml(file_path, jinja2_variables=None, visited=None):
    """Load and return the YAML content from the given file, ensuring includes are processed recursively."""
    if visited is None:
        visited = set()
    if jinja2_variables is None:
        jinja2_variables = {}
    
    if file_path in visited:
        raise ValueError(f"Circular include detected: {file_path}")
    visited.add(file_path)
    
    if not os.path.exists(file_path):
        print_message("error",f"YAML file not found: {file_path}")
        exit(1)
    
    with open(file_path, 'r') as f:
        raw_content = f.read()
    
    # Apply Jinja2 rendering first
    template = Template(raw_content, undefined=StrictUndefined)
    rendered_content = template.render(jinja2_variables)
 
    try:
        content = yaml.safe_load(rendered_content) or {}
    except yaml.YAMLError as e:
        raise ValueError(f"Error parsing YAML after Jinja2 rendering: {e}")
   

    # Apply modification function to include_dirs and files
    # assuming all paths in YAML files are absolute or relative to block top (base_dir) 
    lib_dir = os.path.dirname(file_path)
    block_dir = os.path.dirname(lib_dir)
    if "include_dirs" in content and content["include_dirs"] is not None:
        content["include_dirs"] = [make_path_abs(inc, block_dir) for inc in content["include_dirs"]]
    if "files" in content and content["files"] is not None:
        content["files"] = [make_path_abs(f, block_dir) for f in content["files"]]


    # Process includes recursively
    includes = content.get("include", [])
    if isinstance(includes, str):
        includes = [includes]
    
    for include in includes:
        include_path = os.path.join(lib_dir, include)
        print_message("info", f"***Parsing included YAML - {include_path}")
        included_content = load_yaml(include_path, jinja2_variables, visited)
        
        # Merge included content without restricting to specific keys
        for key, value in included_content.items():
            if key not in content:
                content[key] = value
            else:
                if isinstance(content[key], dict) and isinstance(value, dict):
                    content[key].update(value)
                elif isinstance(content[key], list) and isinstance(value, list):
                    content[key].extend(value)
                else:
                    content[key] = value  # Overwrite with latest value
    
    return content









def get_block_yaml_path(block_type, block_name):
    """Determine the correct YAML path for a block, considering nested structures."""
    wa_root = get_git_root()
    block_path = os.path.abspath(f"{wa_root}/{block_type}/{block_name}/lib/config.yaml")
    return block_path

def resolve_dependencies(block_name, block_type, jinja2_variables=None, visited=None):
    """Recursively resolve dependencies for a given block."""
    if visited is None:
        visited = set()
    
    block_path = get_block_yaml_path(block_type, block_name)
    if block_path in visited:
        print_message("info", f"Skippded already parsed YAML - {block_path}")
        return []  # Avoid circular dependencies
    
    visited.add(block_path)
    print_message("info", f"Parsing {block_type} YAML - {block_path}")
    content = load_yaml(block_path, jinja2_variables)
    dependencies = []
    deps = content.get("dependencies", {})
    if deps is None:
        return dependencies
    
    # Ensure dependencies is a dictionary
    if isinstance(deps, list):
        raise ValueError(f"Invalid dependencies format in {block_path}. Expected dictionary but got list.")
    
    for dep_type, dep_list in deps.items():
        if dep_list is None:
            continue
        if not isinstance(dep_list, list):
            raise ValueError(f"Invalid dependencies format for {dep_type} in {block_path}. Expected list.")
        for dep in dep_list:
            dependencies.extend(resolve_dependencies(dep, dep_type, jinja2_variables, visited))

    dependencies.append(content)  # Append current block after resolving deps
    return dependencies


def parse_attributes(block_name, block_type="verif", attributes = ["include_dirs", "defines", "files", "comp_args", "sim_args"], jinja2_variables = {}):
    """Builds compilation and simulation commands from the YAML dependencies.""" 
    dependencies = resolve_dependencies(block_name, block_type, jinja2_variables)
    
    parsed_attributes = {key: [] for key in attributes}

    for block in dependencies:
        for attrib in attributes:
            if attrib not in block or block[attrib] is None:
                continue
            value = block[attrib]
            if isinstance(value, str):
                value = [value]
            assert isinstance(value, list), f"{attrib} must be a list"
            parsed_attributes[attrib].extend(value)
    
    return parsed_attributes


