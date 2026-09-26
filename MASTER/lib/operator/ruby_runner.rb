# frozen_string_literal: true

require "open3"
require_relative "environment"

module Operator
  module RubyRunner
    module_function

    def ruby_cmd
      return ENV["PUB4_RUBY"] if ENV["PUB4_RUBY"].to_s != ""
      path = rbenv_path("ruby")
      return path if path
      return "ruby34" if executable?("ruby34")
      return "ruby3.4" if executable?("ruby3.4")

      RbConfig.ruby
    end

    def bundle_cmd
      return ENV["PUB4_BUNDLE"] if ENV["PUB4_BUNDLE"].to_s != ""
      path = rbenv_path("bundle")
      return path if path
      return "bundle34" if executable?("bundle34")
      return "bundle3.4" if executable?("bundle3.4")

      "bundle"
    end

    # Resolve the executable from the repo's pinned Ruby instead of trusting the
    # shell's current Ruby. This is the common seam between macOS rbenv and
    # OpenBSD's ruby34/bundle34 binaries: callers receive one executable path,
    # so they do not need to reproduce rbenv's selection logic themselves.
    def rbenv_path(name, root: Environment.repo_root)
      version = pinned_version(root)
      return if version.empty?

      rbenv_root = ENV["RBENV_ROOT"].to_s
      rbenv_root = File.expand_path("~/.rbenv") if rbenv_root.empty?
      direct = File.join(rbenv_root, "versions", version, "bin", name)
      return direct if File.executable?(direct)

      rbenv = ENV["RBENV"].to_s
      rbenv = command_path("rbenv") if rbenv.empty?
      rbenv = File.join(rbenv_root, "bin", "rbenv") if rbenv.empty?
      return unless File.executable?(rbenv)

      output, status = Open3.capture2e(
        { "RBENV_VERSION" => version },
        rbenv, "which", name
      )
      path = output.to_s.strip
      return unless status.success? && File.executable?(path)

      path
    end

    def command_path(name)
      output, status = Open3.capture2e("command", "-v", name)
      status.success? ? output.to_s.strip : ""
    end

    def pinned_version(root)
      path = File.join(root, ".ruby-version")
      File.file?(path) ? File.read(path).strip : ""
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
