# frozen_string_literal: true

module Master
  module Trace
    class EvidenceLog
      OPERATIONAL = /\A(?:ops:|pipeline:rollback|fix_loop:commit|resync:|deploy:)/

      def initialize(root: Master::ROOT)
        @log = EventLog.new(root: root, stream: "evidence")
      end

      def operational?(event) = event.to_s.match?(OPERATIONAL)

      def append(event, payload = {}) = @log.append(event, payload)

      def recent(limit, pattern: nil) = @log.recent(limit, pattern: pattern)
    end
  end
end