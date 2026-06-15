# frozen_string_literal: true

require "fileutils"
require "open3"

module Master
  module Now
    # O307 — boots Falcon web UI from bin/cli.
    class WebServer
      def self.start(config:)
        new(config:).start
      end

      def initialize(config:)
        @config = config
      end

      def start
        return unless ENV["MASTER_WEB"] == "1"

        port = @config["web_port"] || 53187
        host = @config["web_host"] || "127.0.0.1"

        if RUBY_PLATFORM.include?("openbsd")
          running = system("pgrep", "-qf", "falcon.*#{port}")
          token = @config["web_token"]
          url = @config["web_public_url"] || "http://#{host}:#{port}"
          url += "/?token=#{token}" if token
          $stderr.puts "web: #{url} (#{running ? "up" : "down — run: doas rcctl start master"})"
        else
          boot_falcon(host:, port:)
        end
      rescue StandardError => e
        $stderr.puts "web_ui: #{e.message}"
      end

      private

      def boot_falcon(host:, port:)
        web_dir = File.expand_path("../web", Master::ROOT)
        return unless Dir.exist?(web_dir)
        pids_out, = Open3.capture2e("lsof", "-ti", ":#{port}")
        pids_out.split.each { |pid| Process.kill("TERM", pid.to_i) rescue nil }
        sleep 0.5
        secret = WebSecret.stable(@config)
        spawn(
          { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => secret },
          "bundle", "exec", "falcon", "serve", "--bind", "http://#{host}:#{port}",
          chdir: web_dir, out: File::NULL, err: File::NULL
        )
        $stderr.puts "web: http://#{host}:#{port}"
      end
    end

    class WebSecret
      def self.stable(config)
        return config["web_secret_key_base"] if config["web_secret_key_base"].to_s.length >= 64
        require "securerandom"
        secret = SecureRandom.hex(64)
        config["web_secret_key_base"] = secret
        config_path = File.join(Master::ROOT, ".master", "config.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        existing = Master.load_yaml(config_path) rescue {}
        File.write(config_path, existing.merge("web_secret_key_base" => secret).to_yaml)
        secret
      rescue StandardError
        SecureRandom.hex(64)
      end
    end

    class BootBanner
      def self.print
        return unless ENV["MASTER_BOOT_STATUS"] == "1"
        status = Master::Ops::LoopSlot.status
        budget = Master::Ops::ProcessBudget.status
        $stderr.puts "process: safe=#{ENV.fetch("MASTER_SAFE_MODE", "1")} " \
                     "background=#{ENV.fetch("MASTER_BACKGROUND", "0")} " \
                     "web=#{ENV.fetch("MASTER_WEB", "0")} " \
                     "loop=#{status[:selected] || "none"} valid=#{budget[:valid]}"
      end
    end
  end
end