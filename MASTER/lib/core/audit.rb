# frozen_string_literal: true

module MASTER
  module Audit
    LOG_FILE = File.join(MASTER::Paths::VAR_DIR, 'audit.log')

    class << self
      def log(command:, type:, status:, output_length: 0, session_id: nil)
        entry = {
          t: Time.now.utc.strftime('%Y%m%d.%H%M%S'),
          s: session_id,
          type: type,
          cmd: sanitize(command),
          status: status,
          len: output_length
        }

        File.open(LOG_FILE, 'a') { |f| f.puts entry.to_json }
      rescue => e
        # Don't crash on audit failure
        $stderr.puts "audit: #{e.message}" if ENV['DEBUG']
      end

      def sanitize(cmd)
        cmd.to_s[0..200].gsub(/[\r\n]/, ' ')
      end

      def tail(n = 20)
        return [] unless File.exist?(LOG_FILE)
        File.readlines(LOG_FILE).last(n).map { |l| JSON.parse(l, symbolize_names: true) }
      rescue StandardError
        []
      end

      def clear
        File.write(LOG_FILE, '') if File.exist?(LOG_FILE)
      end
    end
  end
end
