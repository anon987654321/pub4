# frozen_string_literal: true

require "fiddle"

module MASTER
  # OpenBSD security primitives - pledge(2) and unveil(2)
  # Restricts system calls and filesystem access for sandboxing
  module Pledge
    class Error < RuntimeError; end

    begin
      LIBC = Fiddle.dlopen(nil)
    rescue Fiddle::DLError
      LIBC = nil
    end

    class << self
      # Check if pledge(2) is available on this platform
      # @return [Boolean] true if running on OpenBSD with pledge support
      def available?
        RUBY_PLATFORM.include?("openbsd") && !LIBC.nil?
      end

      # Restrict process to specified promises
      # @param promises [String] Space-separated list of pledge promises
      # @param execpromises [String, nil] Promises for execve(2) processes
      # @return [void]
      # @raise [Error] if pledge unavailable or call fails
      def pledge(promises, execpromises = nil)
        raise Error, "pledge(2) unavailable on #{RUBY_PLATFORM}" unless available?

        fn = Fiddle::Function.new(
          LIBC["pledge"],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        r = fn.call(promises, execpromises)
        raise Error, "pledge(2) failed: errno #{Fiddle.last_error}" unless r.zero?
      end

      # Restrict filesystem access to specific paths
      # @param path [String] Path to reveal
      # @param permissions [String] Permission string (e.g., "r", "rw", "rx")
      # @return [void]
      # @raise [Error] if unveil unavailable or call fails
      def unveil(path, permissions)
        raise Error, "unveil(2) unavailable on #{RUBY_PLATFORM}" unless available?

        fn = Fiddle::Function.new(
          LIBC["unveil"],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        r = fn.call(path, permissions)
        raise Error, "unveil(2) failed: errno #{Fiddle.last_error}" unless r.zero?
      end
    end
  end
end
