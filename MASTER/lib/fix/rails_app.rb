# frozen_string_literal: true

require "pathname"
require "yaml"

module Master
  module Fix
    # Canonical Rails-tree and app-inventory reads shared by /fix's proofs,
    # visual graph and target selection. RAILS/apps.yml is the app registry;
    # filesystem presence alone must not invent a fourth Rails app.
    module RailsApp
      # Rails by what the tree holds, not by where it sits: a target is Rails when it is inside an app
      # (config/application.rb) or an engine (lib/<name>/engine.rb), or below a directory that holds
      # one, as RAILS/test and RAILS/apps.yml are. The search stops at the repository root, so a
      # Rails project beside the checkout cannot make MASTER read as Rails.
      def self.tree_target?(target, repo_root:)
        root = File.expand_path(repo_root)
        dir = File.expand_path(target.to_s, root)
        dir = File.dirname(dir) unless File.directory?(dir)
        return false unless dir == root || dir.start_with?("#{root}/")

        Pathname(dir).ascend.take_while { |path| path.to_s != root }.any? { |path| rails_dir?(path.to_s) }
      end

      def self.rails_dir?(dir)
        return false unless File.directory?(dir)

        app_or_engine?(dir) ||
          Dir.children(dir).any? { |child| app_or_engine?(File.join(dir, child)) }
      end

      def self.app_or_engine?(dir)
        File.file?(File.join(dir, "config", "application.rb")) ||
          !Dir.glob(File.join(dir, "lib", "*", "engine.rb")).empty?
      end
      private_class_method :rails_dir?, :app_or_engine?

      def self.named_apps(repo_root:)
        registry = File.join(File.expand_path(repo_root), "RAILS", "apps.yml")
        YAML.safe_load_file(registry, aliases: true).fetch("apps").keys.map(&:to_s).sort.freeze
      end

      def self.app_name(target, repo_root:)
        name = relative_path(target, repo_root:)&.match(%r{\ARAILS/([^/]+)(?:/|\z)})&.captures&.first
        name if name && named_apps(repo_root:).include?(name)
      end

      def self.app_root?(target, repo_root:)
        name = app_name(target, repo_root:)
        !!(name && relative_path(target, repo_root:) == "RAILS/#{name}" &&
          File.directory?(File.join(File.expand_path(repo_root), "RAILS", name)))
      end

      def self.relative_path(target, repo_root:)
        root = File.expand_path(repo_root)
        absolute = File.expand_path(target.to_s, root)
        prefix = "#{root}#{File::SEPARATOR}"
        absolute == root ? "." : (absolute.delete_prefix(prefix) if absolute.start_with?(prefix))
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

      # MASTER runs from its own gem store (~/.master/bundler), set before Bundler starts, so
      # with_unbundled_env puts that store back rather than clearing it: the app then booted
      # against MASTER's gems and stopped on bootsnap/setup. These name only MASTER's store and
      # bundle; nil unsets them, and the app's bin/rails finds its own Gemfile. MT_NO_PLUGINS is
      # MASTER's test setting: Rails' test runner is a minitest plugin, and with it off
      # `bin/rails test a_test.rb b_test.rb` ran 0 tests and exited 0.
      FOREIGN_BUNDLE = %w[
        GEM_HOME GEM_PATH RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_LOCKFILE BUNDLE_PATH BUNDLE_APP_CONFIG
        BUNDLE_USER_CONFIG BUNDLE_DISABLE_SHARED_GEMS BUNDLE_FROZEN BUNDLE_BIN_PATH BUNDLER_VERSION BUNDLER_SETUP
        MT_NO_PLUGINS
      ].freeze

      def self.env(root)
        version = File.join(root, ".ruby-version")
        shims = File.expand_path("~/.rbenv/shims")
        FOREIGN_BUNDLE.to_h { |key| [key, nil] }.tap do |env|
          env["RBENV_VERSION"] = File.read(version).strip if File.file?(version)
          env["PATH"] = "#{shims}:#{ENV.fetch("PATH", "")}" if File.directory?(shims)
        end
      end
    end
  end
end
