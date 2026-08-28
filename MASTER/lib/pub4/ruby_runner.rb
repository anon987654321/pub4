# frozen_string_literal: true

require "open3"
require_relative "environment"

module Pub4
  module RubyRunner
    module_function

    def ruby_cmd
      return ENV["PUB4_RUBY"] if ENV["PUB4_RUBY"].to_s != ""
      return "ruby34" if executable?("ruby34")
      return "ruby3.4" if executable?("ruby3.4")

      RbConfig.ruby
    end

    def bundle_cmd
      return ENV["PUB4_BUNDLE"] if ENV["PUB4_BUNDLE"].to_s != ""
      return "bundle34" if executable?("bundle34")
      return "bundle3.4" if executable?("bundle3.4")

      "bundle"
    end

    def gate_ruby
      ruby_cmd
    end

    def runtime_gate_skipped?
      return true if ENV["SKIP_RUNTIME_GATE"] == "1"
      return false if Environment.on_vps? || Environment.on_openbsd?

      !Environment.ruby_version_ok?
    end

    def runtime_skip_reason
      return "SKIP_RUNTIME_GATE=1" if ENV["SKIP_RUNTIME_GATE"] == "1"
      return if Environment.on_vps? || Environment.on_openbsd?
      return if Environment.ruby_version_ok?

      Environment.ruby_mismatch_message
    end

    def executable?(name)
      _, status = Open3.capture2e("command", "-v", name)
      status.success?
    end
  end
end
