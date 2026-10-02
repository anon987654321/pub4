# frozen_string_literal: true

module Master
  module Ground
    # Ruby binding for OpenBSD's pledge(2) and unveil(2) through Fiddle, and a
    # no-op everywhere else. The name is the system call's; OPENBSD/ is the deploy
    # tree and has nothing to do with this module.
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
        def openbsd? = true
      else
        def pledge(*) = nil
        def unveil(*) = nil
        def lock_unveil! = nil
        def openbsd? = false
      end

      GEM_DIRS = [".local/share/gem", ".gem"].freeze
      STAGE1_PROMISES = "stdio rpath wpath cpath proc exec inet dns tty unveil prot_exec error"
      STAGE2_PROMISES = "stdio rpath wpath cpath proc exec inet dns tty prot_exec error"

      Profile = Data.define(:name, :capabilities, :promises) do
        def initialize(name:, capabilities:, promises:)
          super(
            name: name.to_sym,
            capabilities: capabilities.map(&:to_sym).freeze,
            promises: promises.to_s.freeze
          )
        end

        def allows?(capability) = capabilities.include?(capability.to_sym)
      end

      PROFILES = {
        boot: Profile.new(name: :boot, capabilities: %i[stdio read execute], promises: STAGE1_PROMISES),
        model: Profile.new(name: :model, capabilities: %i[stdio read model], promises: "stdio rpath inet dns"),
        fix: Profile.new(name: :fix, capabilities: %i[stdio read write create execute], promises: STAGE2_PROMISES),
        device: Profile.new(name: :device, capabilities: %i[stdio read device], promises: "stdio rpath"),
        world: Profile.new(name: :world, capabilities: %i[stdio read world], promises: "stdio rpath"),
      }.freeze

      def profile(name) = PROFILES.fetch(name.to_sym)

      def apply_profile!(name)
        selected = profile(name)
        pledge(selected.promises)
        selected
      end

      def stage1_boot!(root)
        pledge(STAGE1_PROMISES)
        unveil("/", "")
        unveil(root, "rwc")
        unveil(Dir.home, "rwc")
        unveil("/tmp", "rwc")
        unveil("/bin", "rx")
        unveil("/sbin", "rx")
        unveil("/usr/bin", "rx")
        unveil("/usr/sbin", "rx")
        unveil("/usr/local/bin", "rx")
        unveil("/usr/local/lib", "r")
        unveil("/usr/local/share", "r")
        unveil("/etc/ssl", "r")
        unveil("/etc/resolv.conf", "r")
        unveil("/dev/urandom", "r")
        unveil("/dev/null", "rwc")
        unveil("/var/run", "r")
        GEM_DIRS.each { |d| (dir = File.join(Dir.home, d); unveil(dir, "r") if Dir.exist?(dir)) }
      end

      def stage2_lock!
        lock_unveil!
        pledge(STAGE2_PROMISES)
      end
    end
  end
end
