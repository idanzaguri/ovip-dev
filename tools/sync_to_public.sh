#!/usr/bin/env bash
#
# sync_to_public.sh -- mirror the publishable subset of ovip-dev
#                      to the public ovip repository.
#
# The dev repo is the source of truth for both VIP and tooling. The public
# repo carries ONLY the user-facing subset (no testbench, no runners, no
# tools/, no design notes). This script enforces that separation via an
# explicit allowlist below.
#
# Usage:
#     # one-time setup
#     export OVIP_PUBLIC_REPO=git@github.com:idanzaguri/ovip.git
#
#     # publish current dev HEAD to the public repo's main
#     tools/sync_to_public.sh                 # dry run by default
#     tools/sync_to_public.sh --push          # actually push
#
# The script writes its work into a temp clone of the public repo, force-
# wipes the tracked content, copies the allowlist back in, commits, and
# (with --push) pushes. The script must be run from the dev repo's root.

set -euo pipefail

# -----------------------------------------------------------------------------
# Allowlist: ONLY these paths leave the dev repo.
# If you add a path here, also add it to the corresponding section of the
# public repo's top-level README so adopters know what's available.
# -----------------------------------------------------------------------------
PUBLIC_PATHS=(
    LICENSE
    README.md
    .gitignore
    verif/ovip_common
    verif/ovip_axi
    examples
)

# -----------------------------------------------------------------------------
PUBLIC_REPO=${OVIP_PUBLIC_REPO:-}
DRY_RUN=1
for arg in "$@"; do
    case "$arg" in
        --push)    DRY_RUN=0 ;;
        --repo=*)  PUBLIC_REPO="${arg#--repo=}" ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown arg: $arg (use --help)" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$PUBLIC_REPO" ]]; then
    echo "error: set OVIP_PUBLIC_REPO=... or pass --repo=..." >&2
    exit 2
fi

# Sanity check: are we at the dev repo root?
if [[ ! -d verif/ovip_axi || ! -d examples ]]; then
    echo "error: run this from the ovip-dev repo root" >&2
    exit 2
fi

DEV_SHA=$(git rev-parse --short HEAD)
SCRATCH=$(mktemp -d)
trap "rm -rf '$SCRATCH'" EXIT

echo "[sync] cloning $PUBLIC_REPO -> $SCRATCH"
git clone --depth=1 "$PUBLIC_REPO" "$SCRATCH"

echo "[sync] clearing tracked files in scratch"
(cd "$SCRATCH" && git ls-files -z | xargs -0r rm -f)

echo "[sync] copying allowlisted paths"
for p in "${PUBLIC_PATHS[@]}"; do
    if [[ ! -e "$p" ]]; then
        echo "  warning: $p does not exist; skipping" >&2
        continue
    fi
    echo "  + $p"
    # --relative preserves the directory structure under SCRATCH/
    rsync -a --relative "./$p" "$SCRATCH/"
done

# Drop empty directories that may be left behind from the clear above.
(cd "$SCRATCH" && find . -type d -empty -not -path './.git*' -delete)

cd "$SCRATCH"

if git diff --cached --quiet --exit-code 2>/dev/null && git diff --quiet --exit-code 2>/dev/null; then
    # check both staged and unstaged; fall back to a full status check
    if [[ -z "$(git status --porcelain)" ]]; then
        echo "[sync] nothing to publish (public repo already matches dev HEAD)"
        exit 0
    fi
fi

git add -A
git diff --cached --quiet && { echo "[sync] nothing to commit"; exit 0; }

echo "[sync] staged changes:"
git diff --cached --stat | tail -30

if (( DRY_RUN )); then
    echo "[sync] DRY RUN -- not pushing. Pass --push to publish."
    exit 0
fi

git commit -m "Sync from ovip-dev @ $DEV_SHA"
# Push the local HEAD to the public repo's main, regardless of what local
# branch git happens to have created on clone (modern git defaults vary
# between main / master).
git push origin HEAD:main
echo "[sync] pushed to $PUBLIC_REPO"
