# frozen_string_literal: true

require "json"
require "socket"
require "fileutils"
require "open3"
require_relative "env"
require_relative "profile"

module Master
  module Mobile
    # Measured mobile readiness and local install-integrity checks. This is not
    # a whole-device malware scan; inaccessible Android properties stay unknown.
    class Doctor
      CANONICAL_ORIGINS = [
        "https://github.com/anon987654321/pub4.git",
        "https://github.com/anon987654321/pub4",
        "git@github.com:anon987654321/pub4.git",
        "ssh://git@github.com/anon987654321/pub4.git",
      ].freeze

      def initialize(root:, config: Mobile.config)
        @root = File.expand_path(root)
        @config = config
      end

      def report
        facts = measured
        blocked = blockers(facts)
        facts.merge("status" => blocked.empty? ? "ready" : "blocked", "blocked_by" => blocked)
      end

      private

      def measured
        min_ruby = Profile.new(config: @config).min_ruby
        { "termux" => Env.termux?, "ruby" => RUBY_VERSION, "ruby_ok" => Env.ruby_ok?(min_ruby),
          "packages" => presence("required"), "optional" => presence("optional"), "falcon" => falcon?,
          "state_dir_secure" => state_dir_secure?, "repository_origin_ok" => repository_origin_ok?,
          "checkout_clean" => checkout_clean?, "port" => port_state,
          "speech_to_text" => Env.on_path?(@config.dig("ambient", "stt").to_s),
          "text_to_speech" => Env.on_path?(@config.dig("ambient", "tts").to_s) }
      end

      def blockers(facts)
        { "termux" => facts["termux"], "ruby" => facts["ruby_ok"],
          "packages" => facts["packages"].values.all?, "falcon" => facts["falcon"],
          "state_dir_permissions" => facts["state_dir_secure"],
          "repository_origin" => facts["repository_origin_ok"],
          "checkout_clean" => facts["checkout_clean"] }.reject { |_name, ok| ok }.keys
      end

      def presence(kind)
        Array(@config.dig("packages", kind)).to_h { |name| [name, Env.package_installed?(name)] }
      end

      def falcon?
        Gem::Specification.find_by_name("falcon")
        true
      rescue Gem::MissingSpecError
        false
      end

      def state_dir_secure?
        parent = File.join(@root, ".master")
        dir = File.join(parent, "mobile")
        return false if File.symlink?(parent) || File.symlink?(dir)

        FileUtils.mkdir_p(dir, mode: 0o700)
        File.chmod(0o700, dir)
        stat = File.lstat(dir)
        stat.directory? && !stat.symlink? && (stat.mode & 0o077).zero? && File.writable?(dir)
      rescue SystemCallError
        false
      end

      def repository_origin_ok?
        origin, status = Open3.capture2("git", "-C", @root, "remote", "get-url", "origin")
        status.success? && CANONICAL_ORIGINS.include?(origin.strip)
      rescue SystemCallError
        false
      end

      def checkout_clean?
        _out, status = Open3.capture2("git", "-C", @root, "diff", "--quiet")
        return false unless status.success?

        _out, cached = Open3.capture2("git", "-C", @root, "diff", "--cached", "--quiet")
        cached.success?
      rescue SystemCallError
        false
      end

      def port_state
        port = Integer(@config.dig("bridge", "port") || 8765)
        TCPServer.new(@config.dig("bridge", "bind") || "127.0.0.1", port).close
        "#{port} free"
      rescue Errno::EADDRINUSE
        "#{port} in use"
      end
    end
  end
end
