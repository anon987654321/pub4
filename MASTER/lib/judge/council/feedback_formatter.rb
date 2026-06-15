# frozen_string_literal: true

module Master
  module Judge
    module Council
      # O202: canonical formatter for tribunal and deliberation feedback.
      class FeedbackFormatter
        def self.format(feedback, style: :tribunal, bus: nil)
          case style
          when :feedback then deliberation_feedback(feedback)
          else tribunal_feedback(feedback, bus:)
          end
        end

        def self.tribunal_feedback(feedback, bus: nil)
          judge = feedback.find { |f| f[:role] == "Synthesis" }
          jurors = feedback.reject { |f| f[:role] == "Synthesis" }
          vetoes = jurors.select { |f| f[:veto_role] && f[:feedback].to_s.strip =~ /\AVETO:/i }
          out = []
          out << "verdict: #{judge[:feedback].to_s.strip}" if judge
          unless vetoes.empty?
            out << "" << "vetoes:"
            vetoes.each { |v| out << "  #{v[:persona]}: #{v[:feedback].to_s.strip.sub(/\AVETO:\s*/i, "")}" }
          end
          out << "" << "jurors:"
          jurors.each do |f|
            axiom = f[:axiom] ? "[#{f[:axiom]}] " : ""
            body = f[:feedback].to_s.strip.lines.first(3).map(&:chomp).join(" ")
            out << "  #{axiom}#{f[:persona]} (#{f[:role]}): #{body}"
          end
          conf = safe_confidence(jurors)
          bus&.publish("tribunal:rendered", jurors: jurors.size, vetoes: vetoes.size, judge: !judge.nil?, confidence: conf)
          out.join("\n")
        end

        def self.deliberation_feedback(feedback)
          feedback.map { |f|
            veto = f[:veto_role] ? " [VETO ELIGIBLE]" : ""
            "#{f[:persona]} (#{f[:role]})#{veto}:\n#{f[:feedback].to_s.strip}"
          }.join("\n\n---\n\n")
        end

        def self.safe_confidence(jurors)
          values = jurors.filter_map { |j| j[:confidence] }
          return 0.5 if values.empty?

          (values.sum / values.size.to_f).round(2)
        rescue StandardError
          0.5
        end
      end
    end
  end
end