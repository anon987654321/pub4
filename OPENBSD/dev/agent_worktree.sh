#!/bin/sh
# agent_worktree.sh <agent-name> [base-branch]
#
# Give a coding agent (claude, grok, codex, …) its OWN git worktree + branch off
# the shared pub4 repo, so concurrent agents never share one working tree.
#
# Why: with a shared tree, `git commit -a` sweeps every agent's half-finished
# work into one commit (and `/scan` autofix-by-default can rewrite files another
# agent is mid-edit on). Every commit then needs surgical path-by-path staging.
# Isolated worktrees remove that whole class of hazard: each agent commits freely
# on its own branch; you integrate to main via fast-forward / PR.
#
# Usage:
#   sh OPENBSD/dev/agent_worktree.sh claude
#   cd ../pub4-claude        # work here
#   git push origin agent/claude   # then PR / fast-forward to main
#
# Cleanup:  git worktree remove ../pub4-<agent>
set -eu

agent="${1:?usage: agent_worktree.sh <agent-name> [base-branch]}"
base="${2:-origin/main}"
repo="$(git rev-parse --show-toplevel)"
branch="agent/${agent}"
dir="${repo%/*}/pub4-${agent}"

git -C "$repo" fetch -q origin

if git -C "$repo" worktree list --porcelain | grep -q "worktree ${dir}$"; then
	echo "worktree already exists: ${dir}"
else
	git -C "$repo" worktree add -B "$branch" "$dir" "$base"
fi

echo "worktree: ${dir}"
echo "branch:   ${branch} (from ${base})"
echo "next:     cd ${dir} && work; git push origin ${branch}; then merge/PR to main"
