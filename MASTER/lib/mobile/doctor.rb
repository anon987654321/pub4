# frozen_string_literal: true

require "json"
require "socket"
require "fileutils"
require_relative "env"
require_relative "profile"

module Master
  module Mobile
    # What the phone has and lacks for MASTER, measured rather than assumed.
    # "ready" needs Ruby, every required package, Falcon and a writable
    # .master/mobile; a missing optional package or speech backend is reported
    # and does not block.
    class Doctor
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
          "state_dir_writable" => state_dir_writable?, "port" => port_state,
          "speech_to_text" => Env.on_path?(@config.dig("ambient", "stt").to_s),
          "text_to_speech" => Env.on_path?(@config.dig("ambient", "tts").to_s) }
      end

      def blockers(facts)
        { "ruby" => facts["ruby_ok"], "packages" => facts["packages"].values.all?, "falcon" => facts["falcon"],
          "state_dir" => facts["state_dir_writable"] }.reject { |_name, ok| ok }.keys
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

      def state_dir_writable?
        dir = File.join(@root, ".master", "mobile")
        FileUtils.mkdir_p(dir)
        File.writable?(dir)
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
