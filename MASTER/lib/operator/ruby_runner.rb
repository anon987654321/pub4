# frozen_string_literal: true

require_relative "../io/exec"
require_relative "environment"

module Operator
  module RubyRunner
    module_function

    # The order OPENBSD/lib/ruby_select.sh and bin/ruby use: the newest Ruby the
    # host's packages or Homebrew installed wins, the generic name is last.
    RUBY_NAMES = %w[ruby4.0 ruby40 ruby3.4 ruby34 ruby3.3 ruby33 ruby].freeze

    def ruby_cmd(root: Environment.repo_root)
      explicit = ENV["PUB4_RUBY"].to_s
      return explicit if !explicit.empty? && File.executable?(explicit)

      candidate = best_available_ruby(root:)
      return candidate[:path] if candidate

      raise Environment.ruby_mismatch_message
    end

    def bundle_cmd(root: Environment.repo_root)
      explicit = ENV["PUB4_BUNDLE"].to_s
      return explicit if !explicit.empty? && File.executable?(explicit)

      ruby = best_available_ruby(root:)&.fetch(:path, nil)
      candidates = []
      candidates << File.join(File.dirname(ruby), "bundle") if ruby
      home = File.expand_path("~")
      candidates.concat(
        [
          File.join(home, "bin", "bundle"),
          File.join(home, ".local", "bin", "bundle"),
          File.join(home, ".rbenv", "shims", "bundle"),
        ],
      )
      candidates << openbsd_path("bundle", root:)
      candidates << command_path("bundle")
      candidates.compact.find { |candidate| File.executable?(candidate) } || "bundle"
    end

    def best_available_ruby(root: Environment.repo_root)
      candidates = []
      candidates << RbConfig.ruby if File.executable?(RbConfig.ruby)
      candidates.concat(Dir.glob(File.join(rbenv_root_for(root), "versions", "*", "bin", "ruby")))
      RUBY_NAMES.each do |name|
        path = command_path(name)
        candidates << path unless path.empty?
      end

      candidates.filter_map do |path|
        version = version_for(path)
        next unless version && Environment::SUPPORTED_RUBY_MIN <= version && version < Environment::SUPPORTED_RUBY_MAX

        { path:, version: }
      end.max_by { |candidate| candidate[:version] }
    end

    def rbenv_root_for(_root)
      root = ENV["RBENV_ROOT"].to_s
      root.empty? ? File.expand_path("~/.rbenv") : root
    end

    RBENV_VERSION_DIR = %r{/versions/(\d+(?:\.\d+)+)/bin/ruby\z}

    # Asked of an interpreter only when nothing cheaper knows: the running Ruby says RUBY_VERSION, an rbenv
    # Ruby's directory names its version, and each other path is asked once. Spawning every candidate cost
    # 0.9s of each MASTER boot, because loading check_chain.rb asks for the best Ruby.
    def version_for(path)
      return Gem::Version.new(RUBY_VERSION) if File.identical?(path, RbConfig.ruby)

      named = path.to_s[RBENV_VERSION_DIR, 1]
      return Gem::Version.new(named) if named

      (@versions ||= {}).fetch(path) { @versions[path] = spawned_version(path) }
    end

    def spawned_version(path)
      output, status = Master::Io::Exec.capture2e(path, "-e", "print RUBY_VERSION")
      return unless status.success?

      Gem::Version.new(output.to_s.strip[/\d+(\.\d+)+\z/])
    rescue ArgumentError, Errno::ENOEXEC, Errno::EACCES
      nil
    end

    # Resolve the project-pinned Ruby on rbenv and the supported package Ruby on
    # OpenBSD. Callers receive one executable path and do not reproduce host logic.
    def rbenv_path(name, root: Environment.repo_root)
      version = pinned_version(root)
      return if version.empty?

      rbenv_root = rbenv_root_for(root)
      direct = File.join(rbenv_root, "versions", version, "bin", name)
      return direct if File.executable?(direct)

      rbenv = ENV["RBENV"].to_s
      rbenv = command_path("rbenv") if rbenv.empty?
      rbenv = File.join(rbenv_root, "bin", "rbenv") if rbenv.empty?
      return unless File.executable?(rbenv)

      output, status = Master::Io::Exec.capture2e(
        { "RBENV_VERSION" => version },
        rbenv, "which", name
      )
      path = output.to_s.strip
      return unless status.success? && File.executable?(path)

      path
    end

    def openbsd_path(name, root: Environment.repo_root)
      return unless RUBY_PLATFORM.match?(/openbsd/)

      RUBY_NAMES.each do |ruby_command|
        command = name == "ruby" ? ruby_command : ruby_command.sub(/\Aruby/, name)
        path = command_path(command)
        return path unless path.empty?
      end

      nil
    end

    def command_path(name) = Master::Io::Exec.which(name).to_s

    def pinned_version(root)
      path = File.join(root, ".ruby-version")
      File.file?(path) ? File.read(path).strip : ""
    end

    def check_ruby(root: Environment.repo_root)
      ruby_cmd(root:)
    end

    def runtime_check_skipped?
      return true if ENV["SKIP_RUNTIME_CHECK"] == "1"
      return false if Environment.on_vps? || Environment.on_openbsd?

      !Environment.ruby_version_ok?
    end

    def runtime_skip_reason
      return "SKIP_RUNTIME_CHECK=1" if ENV["SKIP_RUNTIME_CHECK"] == "1"
      return if Environment.on_vps? || Environment.on_openbsd?
      return if Environment.ruby_version_ok?

      Environment.ruby_mismatch_message
    end
  end
end
