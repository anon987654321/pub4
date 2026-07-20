# frozen_string_literal: true

require "fileutils"
require "timeout"

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

    def current_load
      line = `sysctl -n vm.loadavg 2>/dev/null`.strip
      parts = line.split
      return parts[1].to_f if parts.size >= 2

      0.0
    rescue StandardError
      0.0
    end

    def with_lock
      FileUtils.mkdir_p(File.dirname(LOCK_PATH))
      # The 0o666 mode above is masked by the creating process's umask (typically
      # 022), so a file first created by one app's deploy user ends up 0644 --
      # writable only by that user. Every other app then gets Errno::EACCES just
      # opening the file, defeating the whole point of a shared cross-app mutex.
      # chmod isn't subject to umask, so force it explicitly after creation.
      File.open(LOCK_PATH, File::CREAT | File::RDWR, 0o666) do |file|
        File.chmod(0o666, LOCK_PATH)
        unless file.flock(File::LOCK_EX | File::LOCK_NB)
          holder = File.exist?(HOLDER_PATH) ? File.read(HOLDER_PATH).strip : "unknown"
          warn "pub4-ci-guard: #{LOCK_PATH} busy (#{holder})"
          exit 1
        end
        File.write(HOLDER_PATH, holder_info)
        yield
      ensure
        begin
          File.delete(HOLDER_PATH) if File.exist?(HOLDER_PATH)
        rescue Errno::EPERM
          nil
        end
      end
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
