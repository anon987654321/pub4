# frozen_string_literal: true

module Master
  module Fix
    # Runs a command inside one Rails app under the app's own Ruby and bundle,
    # not MASTER's. Run from inside MASTER, bin/rails inherited BUNDLE_GEMFILE
    # and the Homebrew Ruby, failed on bootsnap/setup for all three apps, and
    # the visual pass stopped at "source graph discovery failed" in every /fix.
    module RailsApp
      def self.capture(root, *command, timeout: 300, env: {})
        run = -> { Master::Io::Exec.capture2e(self.env(root).merge(env), *command, chdir: root, timeout:) }
        defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
      end

      def self.env(root)
        version = File.join(root, ".ruby-version")
        shims = File.expand_path("~/.rbenv/shims")
        {}.tap do |env|
          env["RBENV_VERSION"] = File.read(version).strip if File.file?(version)
          env["PATH"] = "#{shims}:#{ENV.fetch("PATH", "")}" if File.directory?(shims)
        end
      end
    end
  end
end
