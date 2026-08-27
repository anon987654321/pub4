# frozen_string_literal: true

require "rbconfig"
require "socket"

module Pub4
  module Environment
    REQUIRED_RUBY = Gem::Version.new("3.4.0")
    REQUIRED_RUBY_MAX = Gem::Version.new("3.5.0")

    module_function

    def repo_root(from: __dir__)
      File.expand_path("../../..", from)
    end

    def on_vps?
      File.file?("/etc/relayd.conf") || ENV["DEPLOY_ASSUME_VPS"] == "1"
    end

    def on_macos?
      RbConfig::CONFIG["host_os"].to_s.include?("darwin")
    end

    def on_openbsd?
      RbConfig::CONFIG["host_os"].to_s.include?("openbsd")
    end

    def ruby_version
      Gem::Version.new(RUBY_VERSION)
    end

    def ruby_version_ok?
      ruby_version >= REQUIRED_RUBY && ruby_version < REQUIRED_RUBY_MAX
    end

    def tree_kind
      cwd = Dir.pwd
      return :deployed_app if cwd.match?(%r{/home/[^/]+/app\z})
      return :dev_checkout if cwd.include?("/home/dev/pub4") ||
                               File.directory?(File.join(repo_root, "OPENBSD")) ||
                               File.directory?(File.join(repo_root, "OPENBSD"))
      :local
    end

    def mode
      return :vps_operator if on_vps?
      return :local_contributor if on_macos? || !on_openbsd?

      :openbsd_local
    end

    def port_open?(port, host = "127.0.0.1")
      socket = Socket.tcp(host, port, connect_timeout: 0.2)
      socket.close
      true
    rescue StandardError
      # A closed/refused/timed-out port is the routine, expected negative
      # result this method exists to report -- not worth Master::Ground::
      # Swallow's ledger, which also isn't loaded in this module's standalone
      # callers (bin/vps-state, integrity_gate.rb) that never boot the full
      # Master:: namespace. Referencing it here raised NameError and masked
      # the real (harmless) connection-refused underneath it.
      false
    end

    def deployed_app_root(app)
      "/home/#{app}/app"
    end

    def dev_repo_root
      ENV.fetch("PUB4_ROOT", "/home/dev/pub4")
    end

    def ruby_label
      "#{RbConfig.ruby} (#{RUBY_VERSION})"
    end

    def ruby_mismatch_message
      return if ruby_version_ok?

      "Ruby #{RUBY_VERSION} detected; pub4 expects ~> 3.4 (use ruby34/bundle34 on OpenBSD or .ruby-version locally)"
    end

    def next_command_for(mode = self.mode)
      case mode
      when :vps_operator
        # after git pull; then ruby34 OPENBSD/integrity_gate.rb
        "zsh OPENBSD/vps_ci.sh <app>"
      when :local_contributor
        if ruby_version_ok?
          "OPENBSD/bin/check && cd MASTER && bin/check --profile=contributor"
        else
          # resolves Ruby 3.4
          "MASTER/bin/ruby OPENBSD/bin/check"
        end
      else
        "OPENBSD/bin/check-full"
      end
    end
  end
end
