# frozen_string_literal: true

require_relative "env"
require_relative "profile"
require_relative "audited_exec"

module Master
  module Mobile
    # Installs the pinned Termux packages before Bundler needs them to build
    # native gems. Off a phone it does nothing and says so.
    class Bootstrap
      Result = Data.define(:ok, :missing, :installed, :messages)

      def initialize(config: Mobile.config, env: ENV, auditor: AuditedExec.new,
                     installed: ->(name) { Env.package_installed?(name) })
        @config = config
        @env = env
        @profile = Profile.new(config:, env:)
        @auditor = auditor
        @installed = installed
      end

      def ensure!
        return done(false, ["Ruby >= #{@profile.min_ruby} required, have #{RUBY_VERSION}"]) unless ruby_ok?
        return done(true, ["not a phone; bootstrap skipped"]) unless Env.mobile?(@env)

        wanted = missing(packages("required"))
        wanted += missing(packages("optional")) if @env["MASTER_MOBILE_INSTALL_OPTIONAL"] == "1"
        return done(true, ["packages present"]) if wanted.empty?
        return asked(wanted) unless @profile.auto_approve?

        install(wanted)
      end

      private

      def ruby_ok? = Env.ruby_ok?(@profile.min_ruby)

      def packages(kind) = Array(@config.dig("packages", kind)).map(&:to_s)

      def missing(names) = names.reject { |name| @installed.call(name) }

      def install(wanted)
        observation = @auditor.pkg_install!(wanted)
        still = missing(wanted)
        messages = [observation.message]
        messages << "still missing after pkg install: #{still.join(', ')}" if still.any?
        Result.new(ok: observation.ok? && still.empty?, missing: still, installed: wanted - still, messages:)
      end

      def asked(wanted)
        Result.new(ok: false, missing: wanted, installed: [],
                   messages: ["missing Termux packages: #{wanted.join(' ')}",
                              "run pkg install #{wanted.join(' ')}, or set MASTER_MOBILE_AUTO_APPROVE=1"])
      end

      def done(ok, messages) = Result.new(ok:, missing: [], installed: [], messages:)
    end
  end
end
