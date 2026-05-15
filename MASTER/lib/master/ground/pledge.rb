# frozen_string_literal: true

module Master
  module Ground
  module Pledge
    module_function

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
        r = LibC.pledge(promises, execpromises || Fiddle::NULL)
        raise SystemCallError.new("pledge", Fiddle.last_error) if r == -1
      end

      def unveil(path, permissions)
        r = LibC.unveil(path, permissions)
        raise SystemCallError.new("unveil", Fiddle.last_error) if r == -1
      end

      def lock_unveil! = LibC.unveil(Fiddle::NULL, Fiddle::NULL)
      def openbsd?     = true
    else
      def pledge(*)    = nil
      def unveil(*)    = nil
      def lock_unveil! = nil
      def openbsd?     = false
    end

    GEM_DIRS = [".local/share/gem", ".gem"].freeze
    STAGE1_PROMISES = "stdio rpath wpath cpath proc exec inet dns tty unveil prot_exec error"
    STAGE2_PROMISES = "stdio rpath wpath cpath proc exec inet dns tty prot_exec error"
    STAGE3_PROMISES = "stdio rpath wpath cpath tty"

    def stage1_boot!(root)
      pledge(STAGE1_PROMISES)
      unveil("/", "")
      unveil(root, "rwc")
      unveil(Dir.home, "rwc")
      unveil("/tmp", "rwc")
      unveil("/usr/bin", "rx")
      unveil("/usr/local/bin", "rx")
      unveil("/usr/local/lib", "r")
      unveil("/usr/local/share", "r")
      unveil("/etc/ssl", "r")
      unveil("/etc/resolv.conf", "r")
      unveil("/dev/urandom", "r")
      unveil("/var/run", "r")
      GEM_DIRS.each { |d| (dir = File.join(Dir.home, d); unveil(dir, "r") if Dir.exist?(dir)) }
    end

    def stage2_lock!
      lock_unveil!
      pledge(STAGE2_PROMISES)
    end

    def stage3_scan_only!
      lock_unveil!
      pledge(STAGE3_PROMISES)
    end
  end
  end
end
