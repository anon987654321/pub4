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
#   bin/operator worktree finish # rebase onto origin/main, push the branch, do not merge main
#
# Cleanup:  git worktree remove ../pub4-<agent>
set -eu

if [ "${1:-}" = "finish" ]; then
  # Rebase onto origin/main and push THIS branch. Do not merge to local main
  # and do not push main: that is how another session's push published
  # commits the owner had not decided to ship.
  repo="$(git rev-parse --show-toplevel)"
  git -C "$repo" fetch -q origin
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  case "$branch" in
    main|master)
      echo "worktree finish: on ${branch} — nothing to finish"
      exit 1
      ;;
  esac
  git -C "$repo" rebase origin/main
  git -C "$repo" push -u origin "HEAD:${branch}"
  echo "worktree finish: ${branch} pushed. It is not on main."
  echo "worktree finish: publish with: git push origin HEAD:main"
  echo "worktree finish: then, from the main checkout: git worktree remove ${repo} && git branch -d ${branch}"
  exit 0
fi

agent="${1:?usage: agent_worktree.sh <agent-name>|finish [base-branch]}"
base="${2:-origin/main}"
repo="$(git rev-parse --show-toplevel)"
branch="agent/${agent}"
dir="${repo%/*}/pub4-${agent}"

git -C "$repo" fetch -q origin

# An existing worktree may hold somebody's unfinished work, and handing it over
# is the shared-checkout hazard this command exists to avoid. Two agents were
# given the same tree in one afternoon: one noticed a stranger's eleven modified
# gate files and moved out, the other worked beside them for an hour. The line
# that told them both was "worktree already exists", which reads as success.
#
# Dirty means occupied. A clean one is a leftover and is safe to reuse.
if git -C "$repo" worktree list --porcelain | grep -q "worktree ${dir}$"; then
  dirt="$(git -C "${dir}" status --porcelain 2>/dev/null)"
  if [ -n "${dirt}" ]; then
    echo "worktree ${dir} is occupied — another session has uncommitted work in it:" >&2
    echo "${dirt}" >&2
    echo "pick another name, or finish that work first" >&2
    exit 1
  fi
  echo "worktree already exists and is clean: ${dir}"
else
  git -C "$repo" worktree add -B "$branch" "$dir" "$base"
fi

echo "worktree: ${dir}"
echo "branch:   ${branch} (from ${base})"
echo "next:     cd ${dir} && work; git push origin ${branch}; then merge/PR to main"
