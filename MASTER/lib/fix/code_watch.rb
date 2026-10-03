# frozen_string_literal: true

require "open3"
require "rbconfig"

module Master
  module Fix
    # /fix runs for hours, and the code it runs is often fixed on origin/main
    # while it does: a detector's false positive, a repair defect. A run that
    # keeps the code it booted with keeps asking the model about findings that
    # no longer exist. Once a minute the stream asks whether origin/main has
    # MASTER code the checkout lacks; if so the pass stops taking files,
    # delivers what it repaired, and the process replaces itself with one on the
    # new code, which resumes at the stream cursor.
    module CodeWatch
      ENABLED = ENV.fetch("MASTER_FIX_HOT_RELOAD", "1") != "0"
      INTERVAL = Integer(ENV.fetch("MASTER_FIX_HOT_RELOAD_S", 60))
      PATHS = %w[MASTER/lib MASTER/law MASTER/data MASTER/bin].freeze

      LOCK = Mutex.new
      @checked_at = nil
      @requested = false

      module_function

      # True once origin/main carries a commit to MASTER's code that HEAD does
      # not; checked at most once an INTERVAL, and sticky once seen.
      def stale?(root)
        return false unless ENABLED

        # Three stream workers ask at once; one of them asks git.
        LOCK.synchronize { check(root) }
      end

      def check(root)
        return true if @requested
        return false if @checked_at && Time.now - @checked_at < INTERVAL

        @checked_at = Time.now
        repo = git(root, "rev-parse", "--show-toplevel")
        return false unless repo && git(repo, "fetch", "-q", "origin", "main")

        count = git(repo, "rev-list", "--count", "HEAD..origin/main", "--", *PATHS).to_i
        return false unless count.positive?

        Master::Trace::Dmesg.status("fix0", "reload: #{count} new MASTER commit(s) on origin/main; finishing the file in hand")
        @requested = true
      end

      def requested? = @requested

      # Brings the checkout up to origin/main and execs the same command again.
      # Work the pass could not deliver (a red proof leaves it in the tree) is
      # carried across the rebase by autostash, not refused: refusing ended the
      # run, and the chain moved to the next tree with MASTER unfinished. A
      # rebase that conflicts is the one case left to a person.
      def reexec!(root, command)
        repo = git(root, "rev-parse", "--show-toplevel")
        unless git(repo, "rebase", "-q", "--autostash", "origin/main")
          git(repo, "rebase", "--abort")
          return Master::Trace::Dmesg.status("fix0", "reload: rebase onto origin/main conflicted; not restarting")
        end

        script = File.join(root, ".master", "fix_reload_command")
        File.write(script, "#{command}\n")
        Master::Trace::Dmesg.status("fix0", "reload: now at #{git(repo, "log", "--oneline", "-1")}; restarting #{command}")
        $stdout.flush
        exec(RbConfig.ruby, File.expand_path($PROGRAM_NAME), in: script)
      end

      def git(dir, *args)
        out, status = Open3.capture2e("git", "-C", dir.to_s, *args)
        status.success? ? out.strip : nil
      end
    end
  end
end
