# frozen_string_literal: true

require "open3"
require "net/http"
require "uri"

module Master
  module Io
    class Relayd
      TIER = :dangerous
      NAME = "relayd".freeze
      DESCRIPTION = "Parse relayd.conf, probe backend /up checks, reload relayd.".freeze
      CONF_PATH = "/etc/relayd.conf".freeze
      BACKEND_RE = /forward\s+to\s+<(\w+)>\s+port\s+(\d+)(?:\s+check\s+http\s+"([^"]+)"\s+code\s+(\d+))?/i.freeze

      def initialize(root: Master::ROOT, event_bus: nil)
        @root = root
        @bus = event_bus
      end

      def call(action: :audit, conf_path: CONF_PATH)
        case action.to_sym
        when :audit then audit(conf_path:)
        when :reload then reload
        when :health then health(conf_path:)
        else Result.err("relayd: unknown action #{action}", category: :validation)
        end
      end

      def audit(conf_path: CONF_PATH)
        return Result.err("relayd: missing #{conf_path}", category: :validation) unless File.file?(conf_path)

        backends = parse_backends(File.read(conf_path))
        checks = backends.map { |backend| probe_backend(backend) }
        @bus&.publish("relayd:audit", backends: backends.size, checks: checks.size)
        Result.ok({ conf_path:, backends:, checks: })
      rescue StandardError => e
        Result.err("relayd: #{e.message}", category: :unknown)
      end

      def health(conf_path: CONF_PATH)
        result = audit(conf_path:)
        return result unless result.ok?

        failures = result.value![:checks].reject { |row| row[:ok] }
        return Result.ok(result.value!) if failures.empty?

        Result.err("relayd: #{failures.size} backend check(s) failed", category: :validation, details: failures)
      end

      def reload
        out, status = Master::Io::Exec.capture2e("doas", "-n", "rcctl", "reload", "relayd")
        @bus&.publish("relayd:reload", ok: status.success?)
        return Result.ok(out.strip) if status.success?

        Result.err("relayd reload failed: #{out.strip}", category: :provider_error)
      rescue StandardError => e
        Result.err("relayd reload: #{e.message}", category: :unknown)
      end

      private

      def parse_backends(source)
        source.each_line.filter_map do |line|
          match = line.match(BACKEND_RE)
          next unless match

          {
            name: match[1],
            port: match[2].to_i,
            check_path: match[3] || "/",
            check_code: (match[4] || "200").to_i,
          }
        end
      end

      def probe_backend(backend)
        path = backend[:check_path]
        uri = URI("http://127.0.0.1:#{backend[:port]}#{path}")
        response = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 8) do |http|
          http.get(uri.request_uri)
        end
        ok = response.code.to_i == backend[:check_code]
        backend.merge(ok:, status: response.code.to_i)
      rescue StandardError => e
        backend.merge(ok: false, status: nil, error: e.message)
      end
    end
  end
end
