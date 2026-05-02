# frozen_string_literal: true

require "fiddle"
require "fiddle/import"

module Master
  module Pledge
    extend self

    if RUBY_PLATFORM.include?("openbsd")
      extend Fiddle::Importer
      dlload "libc.so"
      extern "int pledge(const char *, const char *)"
      extern "int unveil(const char *, const char *)"

      def pledge(promises, execpromises = nil)
        ep = execpromises ? Fiddle::Pointer[execpromises] : Fiddle::NULL
        result = self.__pledge(promises, ep)
        raise SystemCallError.new("pledge failed", Fiddle.last_error) if result == -1
      end

      def unveil(path, permissions)
        result = self.__unveil(path, permissions)
        raise SystemCallError.new("unveil failed", Fiddle.last_error) if result == -1
      end

      def lock_unveil! = unveil(nil, nil)
    else
      def pledge(*) = nil
      def unveil(*) = nil
      def lock_unveil! = nil
    end

    # Stage 1: called before Builder.build -- widest promises, no lock
    def stage1_boot!(root)
      pledge("stdio rpath wpath cpath proc exec inet dns tty unveil")
      unveil("/", "")
      unveil(root, "rwc")
      unveil(Dir.home, "rwc")
      unveil("/tmp", "rwc")
      unveil("/usr/bin", "rx")
      unveil("/usr/local/bin", "rx")
      unveil("/usr/local/lib", "r")
      unveil("/usr/local/share", "r")
      [Dir.home + "/.local/share/gem", Dir.home + "/.gem"].each { |p| unveil(p, "r") if Dir.exist?(p) }
      unveil("/dev/urandom", "r")
    end

    # Stage 2: called after CLI is fully initialized -- lock filesystem
    def stage2_lock!
      pledge("stdio rpath wpath cpath proc exec inet dns tty")
      lock_unveil!
    end

    # Stage 3: scan-only sessions (no network, no exec)
    def stage3_scan_only!
      pledge("stdio rpath wpath cpath tty")
      lock_unveil!
    end

    def openbsd? = RUBY_PLATFORM.include?("openbsd")
  end
end
