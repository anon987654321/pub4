# frozen_string_literal: true

require "fileutils"
require "timeout"
require_relative "load_average"

module Pub4
  # VPS-only mutex + load gate for Rails bin/ci (prevents parallel CI pile-ups on vm23).
  module CiGuard
    LOCK_PATH = ENV.fetch("PUB4_CI_LOCK", "/var/tmp/pub4-ci.lock")
    HOLDER_PATH = "#{LOCK_PATH}.holder".freeze
    MAX_LOAD = ENV.fetch("PUB4_CI_MAX_LOAD", "4").to_f
    TIMEOUT_S = Integer(ENV.fetch("PUB4_CI_TIMEOUT", "3600"))
    VPS_MARKERS = ["/etc/relayd.conf", "/var/db/pub4_vps"].freeze

    module_function

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

    def check_load!
      load = current_load
      return if load <= MAX_LOAD

      warn "pub4-ci-guard: load #{load} exceeds PUB4_CI_MAX_LOAD=#{MAX_LOAD}"
      exit 1
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
      FileUtils.mkdir_p(File.dirname(LOCK_PATH))
      file = open_shared(LOCK_PATH, File::CREAT | File::RDWR)
      begin
        unless file.flock(File::LOCK_EX | File::LOCK_NB)
          warn "pub4-ci-guard: #{LOCK_PATH} busy (#{safe_read(HOLDER_PATH)})"
          exit 1
        end
        write_holder!
        yield
      ensure
        file.close
        begin
          File.delete(HOLDER_PATH) if File.exist?(HOLDER_PATH)
        rescue Errno::EPERM
          nil
        end
      end
    end

    # The 0o666 mode passed to File.open/File.write is masked by the creating
    # process's umask (typically 022), so a file first created by one app's
    # deploy user ends up 0644 -- writable only by that user. chmod isn't
    # subject to umask, so force it explicitly after creation -- but only the
    # file's owner may chmod it at all, so every app after the first hits
    # Errno::EPERM here and that's fine: it means someone already fixed the
    # mode (or this app's own creation already got it right).
    #
    # None of this helps if the file already exists with a stale restrictive
    # mode from before this fix (or a stricter umask) -- opening it for
    # read/write then fails at the OS level with Errno::EACCES, before any
    # chmod call ever runs. That's a real, separate failure a non-owner
    # process cannot self-heal (chmod would also raise EPERM), so it's
    # reported clearly instead of crashing with a raw backtrace.
    def open_shared(path, mode)
      file = File.open(path, mode, 0o666)
      begin
        File.chmod(0o666, path)
      rescue Errno::EPERM
        nil
      end
      file
    rescue Errno::EACCES => e
      warn "pub4-ci-guard: #{path} not accessible (#{e.message}) -- ask its owner to " \
           "chmod 666 it, or delete it if stale"
      exit 1
    end

    def write_holder!
      file = open_shared(HOLDER_PATH, File::CREAT | File::WRONLY | File::TRUNC)
      file.write(holder_info)
    ensure
      file&.close
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
      "#{user}@#{app} pid=#{Process.pid}"
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
