# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    # Canonical Rails-tree and app-inventory reads shared by /fix's proofs,
    # visual graph and target selection. RAILS/apps.yml is the app registry;
    # filesystem presence alone must not invent a fourth Rails app.
    module RailsApp
      def self.tree_target?(target, repo_root:)
        relative = relative_path(target, repo_root:)
        !!(relative == "RAILS" || relative&.start_with?("RAILS/"))
      end

      def self.named_apps(repo_root:)
        path = File.join(File.expand_path(repo_root), "RAILS", "apps.yml")
        data = YAML.safe_load_file(path, aliases: true)
        apps = data.is_a?(Hash) ? data["apps"] : nil
        raise ArgumentError, "RAILS/apps.yml has no apps mapping" unless apps.is_a?(Hash)

        apps.keys.map(&:to_s).sort.freeze
      end

      def self.app_name(target, repo_root:)
        relative = relative_path(target, repo_root:)
        match = relative&.match(%r{\ARAILS/([^/]+)(?:/|\z)})
        name = match && match[1]
        name if name && named_apps(repo_root:).include?(name)
      end

      def self.app_root?(target, repo_root:)
        name = app_name(target, repo_root:)
        return false unless name

        relative = relative_path(target, repo_root:)
        return false unless relative == "RAILS/#{name}"

        path = File.join(File.expand_path(repo_root), relative)
        File.directory?(path) && File.file?(File.join(path, "Gemfile")) &&
          File.file?(File.join(path, "bin", "rails"))
      end

      def self.relative_path(target, repo_root:)
        root = File.expand_path(repo_root)
        raw = target.to_s
        absolute = raw.start_with?(File::SEPARATOR) ? File.expand_path(raw) : File.expand_path(raw, root)
        return unless absolute == root || absolute.start_with?("#{root}#{File::SEPARATOR}")

        absolute == root ? "." : absolute.delete_prefix("#{root}#{File::SEPARATOR}")
      end
      private_class_method :relative_path

      # Runs a command inside one Rails app under the app's own Ruby and bundle,
      # not MASTER's. Run from inside MASTER, bin/rails inherited BUNDLE_GEMFILE
      # and the Homebrew Ruby, failed on bootsnap/setup for all three apps, and
      # the visual pass stopped at "source graph discovery failed" in every /fix.
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
