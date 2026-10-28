# frozen_string_literal: true

require "digest"
require "shellwords"

module Master
  module Ground
    # Gem, path, and binary pre-flight checks.
    class LibraryVerify
      PIN = /\A {4}\S+ \([^)]*\)\s*\z/

      # The gem versions a Gemfile.lock pins, as one digest. Two bundlers on this machine write the
      # same lock with different dependency constraints, json (< 3) or json (< 4), and each rewrites
      # it on boot, so a digest of the whole file changed while no version moved and every cache keyed
      # on it missed. Only the pinned "    name (version)" lines count, not the constraints under them.
      def self.pinned_digest(path)
        return "none" unless File.file?(path)

        Digest::SHA256.hexdigest(File.foreach(path).grep(PIN).join)[0, 16]
      end

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
