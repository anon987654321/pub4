# frozen_string_literal: true

module Master
  module Pledge
    extend self

    if RUBY_PLATFORM.include?("openbsd")
      require "fiddle"
      require "fiddle/import"

      module LibC
        extend Fiddle::Importer
        dlload "libc.so"
        extern "int pledge(const char *, const char *)"
        extern "int unveil(const char *, const char *)"
      end

      def pledge(promises, execpromises = nil)
        result = LibC.pledge(promises, execpromises || Fiddle::NULL)
        raise SystemCallError.new("pledge failed", Fiddle.last_error) if result == -1
      end

      def unveil(path, permissions)
        result = LibC.unveil(path, permissions)
        raise SystemCallError.new("unveil failed", Fiddle.last_error) if result == -1
      end

      def lock_unveil! = LibC.unveil(Fiddle::NULL, Fiddle::NULL)
    else
      def pledge(*) = nil
      def unveil(*) = nil
      def lock_unveil! = nil
    end

    # Stage 1: called before Builder.build -- widest promises, no lock
    # "error" converts unknown-ioctl pledge kills to EPERM so tty gems degrade gracefully.
    def stage1_boot!(root)
      pledge("stdio rpath wpath cpath proc exec inet dns tty unveil prot_exec error")
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
      unveil("/var/run", "r")
    end

    # Stage 2: called after CLI is fully initialized -- lock filesystem
    def stage2_lock!
      lock_unveil!
      pledge("stdio rpath wpath cpath proc exec inet dns tty prot_exec error")
    end

    # Stage 3: scan-only sessions (no network, no exec)
    def stage3_scan_only!
      lock_unveil!
      pledge("stdio rpath wpath cpath tty")
    end

    def openbsd? = RUBY_PLATFORM.include?("openbsd")
  end
end
