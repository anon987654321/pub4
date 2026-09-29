# frozen_string_literal: true

module Master
  module CLI
    # Human-visible information architecture. Machine telemetry remains available
    # under verbose/trace; normal output presents conversation, result, state and
    # only the diagnostic facts an operator can act on.
    module PresentationContract
      LAYERS = %i[conversation result state diagnostic].freeze
      INTERNAL_EVENT = /\A(?:trace|retry|cache|failover|llm|error)\d*[:#]/i

      module_function

      def status_lines(data, verbose: false)
        lines = []
        lines << "master: #{Master::CLI::RuntimeMode.summary(config: data[:config])}"
        lines << git_line(data)
        lines << "service: master #{data.dig(:svc, :state)}" if data.dig(:svc, :state)
        lines << "fix: background #{data[:bg]}, autofix #{data[:af]}" if data[:bg]
        lines << "review: last stage #{data[:stage]}#{data[:verdict]}" if data[:stage]
        lines << "bundle: #{data[:bndl]}" if data[:bndl]
        Array(data[:failures]).each { |failure| lines << "recent failure: #{human_failure(failure)}" }
        Array(data[:rsi]).each { |row| lines << "opportunity: #{human_opportunity(row)}" }
        if verbose && data[:failures]&.any?
          lines << "diagnostic: raw telemetry follows"
          Array(data[:failures]).each { |failure| lines << "  #{failure}" }
        end
        lines.compact.reject(&:empty?)
      end

      def human_failure(value)
        text = value.to_s.strip
        return text unless text.match?(INTERNAL_EVENT)

        event, rest = text.split(/\s+/, 2)
        label = event.to_s.sub(/\d+\z/, "").tr("_", " ")
        rest.to_s.empty? ? label : "#{label}: #{rest}"
      end

      def human_opportunity(row)
        dimension = row[:dimension].to_s.tr("_", " ")
        return dimension unless row[:fail_rate]
        "#{dimension} failed #{(row[:fail_rate].to_f * 100).round}% of #{row[:total]} calls"
      end

      def git_line(data)
        ahead, behind = data[:ahead_behind]
        counts = [
          ("#{ahead} ahead" if ahead.to_i.positive?),
          ("#{behind} behind" if behind.to_i.positive?),
        ].compact
        suffix = [data[:branch], data[:head] && "at #{data[:head]}", *counts,
                  (data[:dirty] ? "dirty" : "clean")].compact.join(" ")
        "git: #{suffix}"
      end
    end
  end
end
