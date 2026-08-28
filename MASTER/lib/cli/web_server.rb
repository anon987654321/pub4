# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "yaml"
require_relative "../voice/tts_supervisor"

module Master
  module CLI
    module WebServer
      # Minimum accepted length (chars) for an existing key -- looser than
      # SECRET_BYTES since SecureRandom.hex(n) produces 2n hex chars, so a
      # freshly generated secret is 128 chars while 64 remains acceptable
      # for one supplied some other way.
      MIN_SECRET_LENGTH = 64
      SECRET_BYTES = 64

      module_function

      def start(config, io: $stderr)
        return unless ENV["MASTER_WEB"] == "1"

        port = config["web_port"] || 53_187
        host = config["web_host"] || "127.0.0.1"
        RUBY_PLATFORM.include?("openbsd") ? openbsd_status(config:, host:, port:, io:) : spawn_local(config:, host:, port:, io:)
      rescue StandardError => e
        io.puts "web_ui: #{e.message}"
      end

      def openbsd_status(config:, host:, port:, io:)
        running = system("pgrep", "-qf", "falcon.*#{port}")
        base_url = config["web_public_url"] || "http://#{host}:#{port}"
        io.puts "web: #{base_url} (#{running ? "up" : "down — run: doas rcctl start master"})"
        io.puts "web: token set (see .master/config.yml)" if config["web_token"].to_s.length >= 8
      end

      def spawn_local(config:, host:, port:, io:)
        web_dir = File.join(Master::ROOT, "web")
        return unless Dir.exist?(web_dir)

        Master.ensure_services!(root: Master::ROOT)
        pids_out, = Master::Io::Exec.capture2e("lsof", "-ti", ":#{port}")
        pids_out.split.each { |pid| Process.kill("TERM", pid.to_i) rescue Errno::ESRCH }
        sleep 0.5
        count = ENV.fetch("FALCON_COUNT", "2")
        env = spawn_env(web_dir).merge(
          "RAILS_ENV" => "production", "SECRET_KEY_BASE" => stable_secret(config),
        )
        spawn(
          env, Gem.ruby, "-S", "bundle", "exec", "falcon", "serve",
          "--bind", "http://#{host}:#{port}", "-n", count,
          chdir: web_dir, out: File::NULL, err: File::NULL, unsetenv_others: true
        )
        io.puts "web: http://#{host}:#{port}"
      end

      # Rails refuses to boot in production without a stable SECRET_KEY_BASE,
      # so a generated one is written back to .master/config.yml; the rescue
      # keeps a config the process cannot persist from blocking the server,
      # at the cost of a session that does not survive a restart.
      def stable_secret(config)
        return config["web_secret_key_base"] if config["web_secret_key_base"].to_s.length >= MIN_SECRET_LENGTH

        secret = SecureRandom.hex(SECRET_BYTES)
        config["web_secret_key_base"] = secret
        persist_secret(secret)
        secret
      rescue StandardError
        SecureRandom.hex(SECRET_BYTES)
      end
      private_class_method :stable_secret

      def persist_secret(secret)
        config_path = File.join(Master::ROOT, ".master", "config.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        existing = YAML.safe_load_file(config_path, permitted_classes: [Symbol], aliases: true) rescue {}
        tmp_path = "#{config_path}.tmp"
        File.write(tmp_path, existing.merge("web_secret_key_base" => secret).to_yaml)
        File.rename(tmp_path, config_path)
      end
      private_class_method :persist_secret

      # Same bug class already found and fixed for TtsSupervisor: the parent
      # MASTER process's own BUNDLE_GEMFILE/BUNDLE_PATH/RUBYLIB point at
      # MASTER's Gemfile, and spawn's env hash merges into (doesn't replace)
      # the inherited environment -- so without stripping these, the spawned
      # `bundle exec falcon` resolved against MASTER's Gemfile.lock, which
      # doesn't have falcon as a dependency, and failed immediately
      # (Bundler::GemNotFound), silently, because err: is File::NULL.
      # Confirmed live: spawn_local printed its success line and returned,
      # but no process was ever actually listening on the port.
      #
      # Invoking via `Gem.ruby, "-S", "bundle"` (not a bare "bundle" PATH
      # lookup, and not TtsSupervisor's own hardcoded
      # "/usr/local/bin:/usr/bin:/bin") because that hardcoded PATH -- which
      # never actually gets exercised by TtsSupervisor itself, since it spawns
      # Gem.ruby directly with an absolute script path, never a PATH-resolved
      # "bundle" command -- doesn't include Homebrew's ARM path
      # (/opt/homebrew/bin), so a bare "bundle" spawn here fell through to
      # the system Ruby's bundler and failed with Gem::GemNotFoundException.
      # `ruby -S bundle` searches Ruby's own known executable paths instead
      # of the OS PATH, portable across Homebrew locations and platforms.
      def spawn_env(web_dir)
        env = { "BUNDLE_GEMFILE" => File.join(web_dir, "Gemfile") }
        Voice::TtsSupervisor::SPAWN_ENV_KEYS.each { |key| env[key] = ENV.fetch(key, "") }
        Voice::TtsSupervisor::BUNDLE_ISOLATION_KEYS.each { |key| env[key] = nil }
        env
      end
    end
  end
end
