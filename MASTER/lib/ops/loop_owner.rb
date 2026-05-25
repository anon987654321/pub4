# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Ops
    module LoopOwner
      DIR = File.join(Master::ROOT, ".master", "active_loop").freeze
      INFO = File.join(DIR, "owner.json").freeze

      module_function

      def claim(name)
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
        return nil unless File.exist?(INFO)

        JSON.parse(File.read(INFO))
      rescue StandardError
        { "loop" => "unknown" }
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
