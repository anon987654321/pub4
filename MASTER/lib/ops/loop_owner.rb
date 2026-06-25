# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Ops
    module LoopOwner
      DIR = File.join(Master::ROOT, ".master", "active_loop").freeze
      INFO = File.join(DIR, "owner.json").freeze
      STALE_SECONDS = 3600

      module_function

      def claim(name)
        cleanup_stale!
        FileUtils.mkdir_p(File.dirname(DIR))
        Dir.mkdir(DIR)
        File.write(INFO, JSON.generate(loop: name.to_s, pid: Process.pid, at: Time.now.utc.iso8601))
        true
      rescue Errno::EEXIST
        false
      end

      def release
        FileUtils.rm_rf(DIR) if Dir.exist?(DIR)
      end

      def active
        cleanup_stale!
        return unless File.exist?(INFO)

        JSON.parse(File.read(INFO))
      rescue StandardError
        { "loop" => "unknown" }
      end

      def cleanup_stale!
        return unless File.exist?(INFO)

        data = JSON.parse(File.read(INFO))
        pid = data["pid"].to_i
        at = Time.iso8601(data["at"].to_s) rescue Time.at(0)
        stale = pid <= 0 || !process_alive?(pid) || (Time.now.utc - at) > STALE_SECONDS
        release if stale
      rescue StandardError
        release
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def with_claim(name)
        return false unless claim(name)

        yield
      ensure
        release
      end
    end
  end
end
