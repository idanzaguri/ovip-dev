import sys
import os
parent_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, parent_dir)
from proj_utils import *

def main():
    block = sys.argv[1]
    wa_root = get_git_root()
    if wa_root:
        test_config = f"{wa_root}/verif/{block}/lib/tests.yaml"
        if os.path.isfile(test_config):
            content = load_yaml(test_config)
            for t in content.get('tests', []):
                print(f"{t['name']}")

if __name__ == "__main__":
    main()
