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
    verif/ovip_axi_stream
    verif/ovip_apb
    verif/ovip_ace
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
DEV_ROOT=$(git rev-parse --show-toplevel)
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

# -----------------------------------------------------------------------------
# Contributor credit: the mirror publishes ONE squashed commit per sync,
# authored by whoever runs this script -- so without help, only the sync-runner
# ever shows on the public repo's GitHub contributor graph. GitHub attributes
# `Co-authored-by:` trailers to the matching account (when the email is tied to
# that GitHub user), so we emit one trailer per contributor whose work is being
# published, reusing their name+email exactly as recorded in ovip-dev history.
#
# Range = dev commits published since the last sync, scoped to the allowlisted
# paths (so only people whose work actually lands in the public repo get
# credited). We recover the previously synced dev SHA from the prior sync
# commit's message; on the first sync (or if that SHA is gone) we credit the
# full history instead. cwd here is the shallow public clone, so `git log -1`
# reads the previous sync commit; dev-repo queries use `git -C "$DEV_ROOT"`.
# -----------------------------------------------------------------------------
LAST_SYNC_SHA=$(git log -1 --format=%B 2>/dev/null \
    | sed -n 's/^Sync from ovip-dev @ \([0-9a-f]\{4,\}\).*/\1/p' | head -1)
if [[ -n "$LAST_SYNC_SHA" ]] && \
   git -C "$DEV_ROOT" cat-file -e "${LAST_SYNC_SHA}^{commit}" 2>/dev/null; then
    CREDIT_RANGE="${LAST_SYNC_SHA}..HEAD"
else
    CREDIT_RANGE="HEAD"
fi

# Credit both the primary authors of the published commits AND anyone already
# named in a Co-authored-by trailer on them (so co-authors -- e.g. an AI pair or
# a patch contributor whose work was applied under the maintainer's name --
# propagate to the public repo too). Skip the sync-runner: they are already the
# commit author, no self-co-author line needed.
SELF_EMAIL=$(git -C "$DEV_ROOT" config user.email || true)
COAUTHOR_TRAILERS=$(
    {
        git -C "$DEV_ROOT" log "$CREDIT_RANGE" --no-merges \
            --format='%an <%ae>' -- "${PUBLIC_PATHS[@]}"
        git -C "$DEV_ROOT" log "$CREDIT_RANGE" --no-merges \
            --format='%(trailers:key=Co-authored-by,valueonly)' -- "${PUBLIC_PATHS[@]}"
    } \
    | sed '/^[[:space:]]*$/d' \
    | sort -u \
    | while IFS= read -r _person; do
          # _person is "Name <email>"; drop the sync-runner by email.
          _pemail=$(printf '%s' "$_person" | sed -n 's/.*<\(.*\)>.*/\1/p')
          [[ -n "$SELF_EMAIL" && "$_pemail" == "$SELF_EMAIL" ]] && continue
          echo "Co-authored-by: $_person"
      done
)

if [[ -n "$COAUTHOR_TRAILERS" ]]; then
    echo "[sync] crediting contributors (range $CREDIT_RANGE):"
    echo "$COAUTHOR_TRAILERS" | sed 's/^/  /'
fi

if (( DRY_RUN )); then
    echo "[sync] DRY RUN -- not pushing. Pass --push to publish."
    exit 0
fi

COMMIT_MSG="Sync from ovip-dev @ $DEV_SHA"
if [[ -n "$COAUTHOR_TRAILERS" ]]; then
    # Blank line before the trailer block so GitHub parses the trailers.
    COMMIT_MSG+=$'\n\n'"$COAUTHOR_TRAILERS"
fi
git commit -m "$COMMIT_MSG"
# Push the local HEAD to the public repo's main, regardless of what local
# branch git happens to have created on clone (modern git defaults vary
# between main / master).
git push origin HEAD:main
echo "[sync] pushed to $PUBLIC_REPO"
