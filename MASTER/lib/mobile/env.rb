# frozen_string_literal: true

require "yaml"

module Master
  module Mobile
    CONFIG_PATH = File.expand_path("../../data/mobile.yml", __dir__)

    # data/mobile.yml, read once. A missing or unreadable file is an empty profile.
    def self.config(path = CONFIG_PATH)
      @config ||= {}
      @config[path] ||= File.file?(path) ? (YAML.safe_load_file(path) || {}) : {}
    end

    # Probes of the phone this runs on. Nothing here changes anything.
    module Env
      module_function

      def termux?(env = ENV)
        return true if env["TERMUX_VERSION"]
        return true if env["PREFIX"].to_s.include?("com.termux")

        File.directory?("/data/data/com.termux")
      end

      def forced_mobile?(env = ENV) = env["MASTER_PROFILE"].to_s.strip == "mobile"

      def mobile?(env = ENV) = forced_mobile?(env) || termux?(env)

      # `command -v` is a shell builtin, so system("command", ...) never finds
      # anything; the PATH walk is done here instead.
      def on_path?(name, env = ENV)
        env["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, name.to_s)
          File.file?(path) && File.executable?(path)
        end
      end

      def package_installed?(name)
        name = name.to_s
        return false if name.empty?
        return system("dpkg", "-s", name, out: File::NULL, err: File::NULL) if on_path?("dpkg")

        on_path?(name)
      end

      def ruby_ok?(min_version)
        Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(min_version.to_s)
      rescue ArgumentError
        false
      end
    end
  end
end
