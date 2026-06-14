# frozen_string_literal: true

require "open3"
require_relative "web_secret"

module Master
  module Now
    module WebServer
      module_function

      def start(config, io: $stderr)
        return unless ENV["MASTER_WEB"] == "1"

        port = config["web_port"] || 53187
        host = config["web_host"] || "127.0.0.1"
        RUBY_PLATFORM.include?("openbsd") ? openbsd_status(config, host, port, io) : spawn_local(config, host, port, io)
      rescue StandardError => e
        io.puts "web_ui: #{e.message}"
      end

      def openbsd_status(config, host, port, io)
        running = system("pgrep", "-qf", "falcon.*#{port}")
        token = config["web_token"]
        url = config["web_public_url"] || "http://#{host}:#{port}"
        url += "/?token=#{token}" if token
        io.puts "web: #{url} (#{running ? "up" : "down — run: doas rcctl start master"})"
      end

      def spawn_local(config, host, port, io)
        web_dir = File.join(Master::ROOT, "web")
        return unless Dir.exist?(web_dir)

        pids_out, = Open3.capture2e("lsof", "-ti", ":#{port}")
        pids_out.split.each { |pid| Process.kill("TERM", pid.to_i) rescue nil }
        sleep 0.5
        spawn(
          { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => WebSecret.stable(config) },
          "bundle", "exec", "falcon", "serve", "--bind", "http://#{host}:#{port}",
          chdir: web_dir, out: File::NULL, err: File::NULL
        )
        io.puts "web: http://#{host}:#{port}"
      end
    end
  end
end
