# frozen_string_literal: true

module Master
  module Ground
    # rules.yml library_verify — gem, path, and binary pre-flight checks.
    class LibraryVerify
      def initialize(root: Master::ROOT)
        @root = root
        @gemfile_lock = File.join(root, "Gemfile.lock")
      end

      def verify_gem!(name, version: nil)
        return Result.ok(name) unless File.file?(@gemfile_lock)

        lock = File.read(@gemfile_lock)
        pattern = version ? /^\s+#{Regexp.escape(name)} \(#{Regexp.escape(version)}\)/ : /^\s+#{Regexp.escape(name)} /
        return Result.ok(name) if lock.match?(pattern)

        Result.err("library_verify: #{name} missing from Gemfile.lock", category: :validation)
      end

      def verify_path!(relative)
        full = File.expand_path(relative, @root)
        return Result.ok(full) if File.exist?(full)

        Result.err("library_verify: path missing #{relative}", category: :validation)
      end

      def verify_binary!(cmd)
        which = `command -v #{Shellwords.escape(cmd)} 2>/dev/null`.strip
        return Result.ok(which) unless which.empty?

        Result.err("library_verify: binary not on PATH: #{cmd}", category: :validation)
      end
    end
  end
end

require "shellwords"
