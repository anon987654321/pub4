# frozen_string_literal: true

module Master
  module Ground
    # Ruby binding for OpenBSD's pledge(2) and unveil(2) through Fiddle, and a
    # no-op everywhere else. The name is the system call's; OPENBSD/ is the deploy
    # tree and has nothing to do with this module.
    module Pledge
      module_function

      # OpenBSD returns -1 and sets errno when a security restriction fails.
      # Keep the result check portable so refusal behavior can be unit-tested off-host.
      def checked_syscall!(operation, result, error = nil)
        raise SystemCallError.new(operation, error) if result == -1

        result
      end

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
          checked_syscall!("pledge", LibC.pledge(promises, execpromises || Fiddle::NULL), Fiddle.last_error)
        end

        def unveil(path, permissions)
          checked_syscall!("unveil", LibC.unveil(path, permissions), Fiddle.last_error)
        end

        # Locking is the last filesystem boundary in boot. A rejected syscall
        # must abort boot instead of claiming the process has a fixed view.
        def lock_unveil!
          checked_syscall!("unveil", LibC.unveil(Fiddle::NULL, Fiddle::NULL), Fiddle.last_error)
        end
        def openbsd? = true
      else
        def pledge(*) = nil
        def unveil(*) = nil
        def lock_unveil! = nil
        def openbsd? = false
      end

      GEM_DIRS = [".local/share/gem", ".gem"].freeze
      STAGE2_PROMISES = "stdio rpath wpath cpath proc exec inet dns tty prot_exec error"
      STAGE1_PROMISES = "#{STAGE2_PROMISES} unveil"

      # Always set execpromises before the first child can spawn. OpenBSD otherwise
      # starts exec'd children without pledge; a wheel/doas caller could then execute
      # a setuid helper outside this process's promise restrictions. With execpromises
      # set, OpenBSD refuses setuid/setgid execs and descendants inherit this profile.
      EXEC_PROMISES = STAGE2_PROMISES

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
        pledge(STAGE1_PROMISES, EXEC_PROMISES)
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
        pledge(STAGE2_PROMISES, EXEC_PROMISES)
      end
    end
  end
end
