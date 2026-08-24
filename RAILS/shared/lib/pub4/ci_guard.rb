# frozen_string_literal: true

require "fileutils"
require "timeout"
require_relative "load_average"

module Pub4
  # VPS-only mutex + load gate for Rails bin/ci (prevents parallel CI pile-ups on vm23).
  module CiGuard
    # The one CI lock, shared with the shell side.
    #
    # This used to be /var/tmp/pub4-ci.lock while OPENBSD/lib/ci_lock.sh called
    # itself "the one definition of the pub4 CI mutex path" and pointed three
    # shell scripts at /var/db/pub4/ci.lock. Two files, no mutual exclusion
    # between them — and the half that was actually being locked was the half
    # left in world-writable /var/tmp, which is precisely what that rewrite was
    # written to fix. It moved the callers that were not locking anything.
    #
    # An override is honoured only when its directory is not world-writable.
    # That is the property the /var/tmp objection was about: a fixed name in a
    # directory anyone can write to is a symlink an attacker plants and root
    # then chmods. Checking the directory lets a test point this at a private
    # tmpdir without reopening the hole, which hardcoding one path would not.
    LOCK_DIR = "/var/db/pub4"
    DEFAULT_LOCK_PATH = File.join(LOCK_DIR, "ci.lock")

    # Resolved per call rather than frozen into a constant at load: the override
    # is an environment variable, and a constant read at require time cannot see
    # one set afterwards -- which is every test, and every caller that sets it
    # between loading this file and running CI.
    MAX_LOAD = ENV.fetch("PUB4_CI_MAX_LOAD", "4").to_f
    TIMEOUT_S = Integer(ENV.fetch("PUB4_CI_TIMEOUT", "3600"))
    VPS_MARKERS = [ "/etc/relayd.conf", "/var/db/pub4_vps" ].freeze

    module_function

    def lock_path(requested = ENV["PUB4_CI_LOCK"].to_s)
      return DEFAULT_LOCK_PATH if requested.empty?

      dir = File.dirname(requested)
      return DEFAULT_LOCK_PATH unless File.directory?(dir)
      return requested if (File.stat(dir).mode & 0o002).zero?

      warn "pub4-ci-guard: ignoring PUB4_CI_LOCK=#{requested} — #{dir} is world-writable"
      DEFAULT_LOCK_PATH
    rescue SystemCallError
      DEFAULT_LOCK_PATH
    end

    def holder_path = "#{lock_path}.holder"

    def enabled?
      return true if ENV["PUB4_CI_GUARD"] == "1"
      return false if ENV["PUB4_CI_GUARD"] == "0"

      vps_host?
    end

    def vps_host?
      VPS_MARKERS.any? { |path| File.exist?(path) }
    end

    def run!
      return yield unless enabled?

      check_load!
      with_lock { with_timeout { yield } }
    end

    # Waits for the box to settle rather than giving up on it.
    #
    # This exited immediately, and it runs from inside bin/ci — which vps_ci
    # starts *after* it has already synced the tracked tree into /home/<app>/app.
    # So a load spike did not decline to run CI, it abandoned a half-applied
    # deploy: new code live, and on 2026-08-14 no compiled assets behind it.
    #
    # Waiting is the right shape because the spike is self-inflicted and short.
    # `vps-deploy all` deploys four apps back to back, and brgen's CI met the
    # load of the three around it: measured at 3.32, 4.04, 3.43 across the run
    # and 0.32 half an hour later on the same commit, which then passed. A
    # deploy that waits four minutes for its own predecessor to finish is a
    # deploy that works; one that exits is an outage plus a retry.
    #
    # Bounded, because waiting forever on a genuinely wedged box is just a
    # slower failure — and it still exits 1 at the end, so nothing downstream
    # has to learn a new outcome.
    # Read per call, not frozen at require time — the same reason the note above
    # MAX_LOAD gives, and the reason a test can set the budget to zero and get
    # the give-up branch without sleeping for ten minutes to reach it.
    def load_wait_total_s = Integer(ENV.fetch("PUB4_CI_LOAD_WAIT", "600"))
    def load_wait_step_s = Integer(ENV.fetch("PUB4_CI_LOAD_WAIT_STEP", "20"))

    def check_load!
      budget = load_wait_total_s
      waited = 0
      loop do
        load = current_load
        return if load <= MAX_LOAD

        if waited >= budget
          warn "pub4-ci-guard: load #{load} still over PUB4_CI_MAX_LOAD=#{MAX_LOAD} after #{waited}s — giving up"
          exit 1
        end

        warn "pub4-ci-guard: load #{load} over #{MAX_LOAD}, waiting (#{waited}/#{budget}s)"
        sleep load_wait_step_s
        waited += load_wait_step_s
      end
    end

    # Unreadable load fails open here, unlike PruneGuestUsersJob, and on
    # purpose: this gate stands in front of CI, so treating unknown as busy
    # would make an unreadable sysctl look exactly like a permanently locked
    # box and block every deploy. The warning is the difference between failing
    # open and not noticing — the old version returned 0.0 in silence, which
    # reads in the log as an idle machine.
    def current_load
      load5 = LoadAverage.five
      return load5 if load5

      warn "pub4-ci-guard: cannot read load average, proceeding ungated"
      0.0
    end

    def with_lock
      # /var/db/pub4 is root-owned and created by pub4_ensure_ci_lock. Making it
      # here is only for the case where it is already there, so a failure to
      # create is not a failure to lock — open_shared reports that properly.
      # Resolved once per run: calling lock_path repeatedly would re-warn about
      # a rejected override on every use, and could disagree with itself if the
      # environment changed underneath.
      path = lock_path
      holder = "#{path}.holder"

      begin
        FileUtils.mkdir_p(File.dirname(path))
      rescue SystemCallError
        nil
      end

      file = open_shared(path)
      begin
        unless file.flock(File::LOCK_EX | File::LOCK_NB)
          warn "pub4-ci-guard: #{path} busy — #{busy_detail(path, holder)}"
          exit 1
        end
        write_holder!(holder)
        yield
      ensure
        file.close
        begin
          File.delete(holder) if File.exist?(holder)
        rescue SystemCallError
          nil
        end
      end
    end

    # Read-only, because flock(2) does not need write permission — and that is
    # the whole reason this file no longer has to be world-writable.
    #
    # The history is worth keeping, because it is what 0o666 was for. The lock
    # is opened by three different deploy users (brgen, amber, bsdports). Asking
    # for O_RDWR meant the file had to be writable by all of them, which meant
    # chmod 666, which meant: the requested 0o666 on File.open is masked by the
    # creating process's umask down to 0644 (broke amber's deploy 2026-07-20,
    # EACCES, right after brgen's CI created the file); chmod is not subject to
    # umask so it was applied explicitly; only an owner may chmod, so the next
    # app hit EPERM and crashed (bsdports, same incident); and the result was a
    # world-writable file in a world-writable directory, which is the symlink
    # hazard OPENBSD/lib/ci_lock.sh was written to remove.
    #
    # Opening read-only deletes that entire chain. The file can be 0644 and
    # owned by whoever created it; every app can still take the lock.
    def open_shared(path)
      File.open(path, File::RDONLY)
    rescue Errno::ENOENT
      # Create it once, then reopen read-only so the rest of the run holds the
      # same kind of descriptor whether or not it was here already.
      File.open(path, File::CREAT | File::WRONLY, 0o644).close
      File.open(path, File::RDONLY)
    rescue Errno::EACCES, Errno::EPERM => e
      warn "pub4-ci-guard: #{path} not readable (#{e.message}) -- ask its owner to " \
           "chmod 644 it, or delete it if stale"
      exit 1
    end

    # Best effort. A holder note is a diagnostic; a mutex that refuses to be
    # taken because it could not write a comment about itself would be worse
    # than one nobody can attribute. The 2026-08-14 collision between two agents
    # deploying at once was read straight off this file.
    def write_holder!(path = holder_path)
      File.write(path, holder_info)
    rescue SystemCallError
      nil
    end

    def safe_read(path)
      return "unknown" unless File.exist?(path)

      File.read(path).strip
    rescue Errno::EACCES, Errno::ENOENT
      "unknown"
    end

    def holder_info
      user = ENV["USER"] || ENV["LOGNAME"] || "unknown"
      app = File.basename(Dir.pwd)
      "#{user}@#{app} pid=#{Process.pid} since=#{Time.now.utc.strftime('%H:%M:%SZ')}"
    end

    # "busy (unknown)" is accurate and unusable: it cannot distinguish a
    # live CI run from a lock whose holder note was lost, and it gives nobody
    # a next step. Age always exists, so it is always said — a lock held for
    # four seconds and one held for forty minutes want different responses.
    def busy_detail(path, holder)
      note = safe_read(holder).to_s.strip
      age = begin
        secs = (Time.now - File.mtime(path)).to_i
        secs < 120 ? "#{secs}s" : "#{secs / 60}m"
      rescue SystemCallError
        "age unknown"
      end

      if note.empty? || note == "unknown"
        "held #{age}, holder note absent (killed run, or the shell side took it)"
      else
        "held #{age} by #{note}"
      end
    end

    def with_timeout
      return yield if TIMEOUT_S <= 0

      Timeout.timeout(TIMEOUT_S) { yield }
    rescue Timeout::Error
      warn "pub4-ci-guard: CI exceeded PUB4_CI_TIMEOUT=#{TIMEOUT_S}s"
      exit 1
    end
  end
end
