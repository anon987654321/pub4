# frozen_string_literal: true

module Operator

  # Every branch against main, one line each, and whether it is safe to merge.
  #
  # Merging by hand meant five ad-hoc git calls per branch and still merged a
  # branch whose agent was mid-push, with a test that did not parse. The state
  # is worked out once, here, and the answer is a word: merged, active,
  # conflicts, deletes_heavily or ready. Only merged and ready are ever acted
  # on; the others name what to wait for or look at.
  module Branches
    ACTIVE_SECONDS = 3600
    DELETION_WARN = 5_000
    SKIP = %w[main origin/main origin/HEAD origin].freeze
    LINE = "%-16s %-52s +%-3d -%-3d %5dm %6d deleted %s"

    Ref = Data.define(:name, :stamp, :worktree)
    Row = Data.define(:ref, :ahead, :behind, :age, :deleted, :worktree, :state)

    module_function

    # A branch pushed to inside the hour has an agent behind it, and merging it
    # then takes half a feature. Conflicts and mass deletion are only worth
    # reporting for a branch that is otherwise finished.
    def classify(ahead:, age:, deleted:, conflicts:)
      return :merged if ahead.zero?
      return :active if age < ACTIVE_SECONDS
      return :conflicts if conflicts

      deleted > DELETION_WARN ? :deletes_heavily : :ready
    end

    def rows(root:, now: Time.now)
      refs(root).map { |found| row(root, found, now) }
    end

    def render(rows)
      return "branches: none besides main" if rows.empty?

      rows.map do |r|
        format(LINE, r.state, r.ref, r.ahead, r.behind, r.age / 60, r.deleted, r.worktree)
      end.join("\n")
    end

    def refs(root)
      format = "%(refname:short)%09%(committerdate:unix)%09%(worktreepath)"
      out = git(root, "for-each-ref", "--format=#{format}", "refs/heads", "refs/remotes")
      out.lines.map { |line| Ref.new(*line.chomp.split("\t", 3)) }.reject { |found| SKIP.include?(found.name) }
    end

    def row(root, found, now)
      ref = found.name
      ahead = git(root, "rev-list", "--count", "main..#{ref}").to_i
      behind = git(root, "rev-list", "--count", "#{ref}..main").to_i
      age = (now - Time.at(found.stamp.to_i)).to_i
      deleted = ahead.zero? ? 0 : deleted_lines(root, ref)
      conflicts = ahead.positive? && !mergeable?(root, ref)
      state = classify(ahead:, age:, deleted:, conflicts:)
      Row.new(ref:, ahead:, behind:, age:, deleted:, worktree: found.worktree.to_s, state:)
    end

    def deleted_lines(root, ref)
      git(root, "diff", "--numstat", "main...#{ref}").each_line.sum { |line| line.split("\t")[1].to_i }
    end

    def mergeable?(root, ref)
      _, status = Master::Io::Exec.capture2e("git", "merge-tree", "--write-tree", "main", ref, chdir: root)
      status.success?
    end

    def git(root, *args)
      out, = Master::Io::Exec.capture2e("git", *args, chdir: root)
      out
    end
  end
end
