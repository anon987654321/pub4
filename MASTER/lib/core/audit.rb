# frozen_string_literal: true

module MASTER
  module Audit
    LOG_FILE = File.join(MASTER::Paths.var, 'audit.log')
    MAX_CMD_LENGTH = 200

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

      # Log principle violation as event
      def log_violation(violation:, file:, line: nil, session_id: nil)
        event = create_violation_event(
          violation: violation,
          file: file,
          line: line,
          session_id: session_id
        )
        
        # Log to audit trail
        File.open(LOG_FILE, 'a') { |f| f.puts event.to_json }
        
        # Publish to event bus if available
        publish_violation_event(event)
        
        event
      rescue => e
        $stderr.puts "audit violation: #{e.message}" if ENV['DEBUG']
        nil
      end

      def create_violation_event(violation:, file:, line:, session_id:)
        {
          t: Time.now.utc.strftime('%Y%m%d.%H%M%S'),
          s: session_id,
          type: 'violation',
          principle: violation[:principle],
          severity: violation[:severity] || 'medium',
          file: file,
          line: line,
          message: violation[:message]
        }
      end

      def publish_violation_event(event)
        # Publish to event bus
        Events::Bus.publish(
          Events::Event.new(
            type: 'principle_violation',
            data: event,
            timestamp: Time.now
          )
        ) if defined?(Events::Bus)
      rescue => e
        # Don't fail if event bus unavailable
        $stderr.puts "event bus publish failed: #{e.message}" if ENV['DEBUG']
      end

      # Get violation metrics
      def violation_metrics(since: Time.now - 86400)
        violations = tail(1000).select { |e| e[:type] == 'violation' }
        
        since_timestamp = since.utc.strftime('%Y%m%d.%H%M%S')
        recent = violations.select { |v| v[:t] >= since_timestamp }
        
        by_principle = recent.group_by { |v| v[:principle] }
        by_severity = recent.group_by { |v| v[:severity] }
        
        {
          total: recent.size,
          by_principle: by_principle.transform_values(&:size),
          by_severity: by_severity.transform_values(&:size),
          timeline: recent.map { |v| { time: v[:t], principle: v[:principle] } }
        }
      end

      def sanitize(cmd)
        cmd.to_s[0..MAX_CMD_LENGTH].gsub(/[\r\n]/, ' ')
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
