#!/bin/sh
# Exits 0 when a release may run on the commit the workflow is on, and 1 with the reason otherwise. The release
# workflow runs this before it builds or publishes, so a run from another branch, or a tag on one, can never create
# the release GitHub marks as the latest and offers to every installed Library.
#
# A manual run (workflow_dispatch) can start on any branch, so it is allowed on main by name. A tag can point at any
# commit, so it is allowed only when main reaches that commit; the clone must have origin/main fetched first.
#
# Usage: check-release-branch.sh <event> <ref> [<commit>]
#   event   GITHUB_EVENT_NAME, workflow_dispatch or push
#   ref     GITHUB_REF, such as refs/heads/main or refs/tags/v1.2.0
#   commit  GITHUB_SHA to test for a tag; defaults to HEAD
event="${1-}"
ref="${2-}"
commit="${3-HEAD}"

refuse() {
    echo "Refusing the release: $1" >&2
    exit 1
}

if [ "$event" = "workflow_dispatch" ]; then
    # A commit that main merely reaches is not enough here: a branch left on an older commit would pass that and
    # publish old code, so a manual run is allowed on main itself.
    [ "$ref" = "refs/heads/main" ] || refuse "run it from main, not $ref."
    exit 0
fi

# git merge-base exits non-zero for a commit it does not have too, so a missing commit fails closed.
git merge-base --is-ancestor "$commit" origin/main 2>/dev/null \
    || refuse "commit $commit is not on main. Point the tag at a commit on main."
exit 0
