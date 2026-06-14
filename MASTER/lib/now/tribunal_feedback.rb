# frozen_string_literal: true

module Master
  module Now
    class TribunalFeedback
      def initialize(feedback, event_bus: nil)
        @feedback = feedback
        @event_bus = event_bus
      end

      def render
        lines = []
        lines << "verdict: #{judge[:feedback].to_s.strip}" if judge
        append_vetoes(lines)
        append_jurors(lines)
        publish_rendered
        lines.join("\n")
      end

      def render_full
        feedback.map { |item| full_item(item) }.join("\n\n---\n\n")
      end

      private

      attr_reader :feedback, :event_bus

      def judge
        @judge ||= feedback.find { |item| item[:role] == "Synthesis" }
      end

      def jurors
        @jurors ||= feedback.reject { |item| item[:role] == "Synthesis" }
      end

      def vetoes
        @vetoes ||= jurors.select { |item| item[:veto_role] && item[:feedback].to_s.strip =~ /\AVETO:/i }
      end

      def append_vetoes(lines)
        return if vetoes.empty?

        lines << "" << "vetoes:"
        vetoes.each { |item| lines << "  #{item[:persona]}: #{item[:feedback].to_s.strip.sub(/\AVETO:\s*/i, "")}" }
      end

      def append_jurors(lines)
        lines << "" << "jurors:"
        jurors.each { |item| lines << juror_line(item) }
      end

      def juror_line(item)
        axiom = item[:axiom] ? "[#{item[:axiom]}] " : ""
        body = item[:feedback].to_s.strip.lines.first(3).map(&:chomp).join(" ")
        "  #{axiom}#{item[:persona]} (#{item[:role]}): #{body}"
      end

      def full_item(item)
        veto = item[:veto_role] ? " [VETO ELIGIBLE]" : ""
        "#{item[:persona]} (#{item[:role]})#{veto}:\n#{item[:feedback].to_s.strip}"
      end

      def confidence
        values = jurors.filter_map { |item| item[:confidence] || 0.5 }
        (values.sum / [jurors.size, 1].max).round(2)
      rescue StandardError
        0.5
      end

      def publish_rendered
        event_bus&.publish("tribunal:rendered", jurors: jurors.size, vetoes: vetoes.size, judge: !judge.nil?, confidence: confidence)
      end
    end
  end
end
