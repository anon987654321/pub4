# frozen_string_literal: true

module Learnings
  module Reflection
    DEFAULT_MAX_REFLECTIONS = 20
    DEFAULT_CONTEXT_LIMIT = 2_000
    DEFAULT_SENTENCE_LIMIT = 3
    DEFAULT_RECENCY_HALF_LIFE_DAYS = 14.0

    def weighted_reflections(reflections, now: Time.now, half_life_days: DEFAULT_RECENCY_HALF_LIFE_DAYS)
      reflections.map do |reflection|
        reflection.merge(weight: reflection_weight(reflection, now: now, half_life_days: half_life_days))
      end.sort_by { |reflection| -reflection[:weight].to_f }
    end

    def build_context_string(reflections, limit: DEFAULT_CONTEXT_LIMIT)
      selected = take_by_character_budget(reflections, limit: limit)
      header = "Reflection context (most relevant first):"
      body = selected.map.with_index(1) { |reflection, idx| format_reflection_line(reflection, idx) }.join("\n")
      [header, body].reject(&:empty?).join("\n")
    end

    def summarize_reflections(reflections, max_reflections: DEFAULT_MAX_REFLECTIONS, sentence_limit: DEFAULT_SENTENCE_LIMIT)
      selected = reflections.first(max_reflections)
      return "" if selected.empty?

      key_points = selected.map { |reflection| extract_key_point(reflection) }.compact
      key_points = key_points.uniq.first(sentence_limit)
      return "" if key_points.empty?

      key_points.join(" ")
    end

    private

    def reflection_weight(reflection, now:, half_life_days:)
      base_score = reflection[:score].to_f
      created_at = coerce_time(reflection[:created_at] || reflection[:timestamp]) || now
      age_days = [(now - created_at) / 86_400.0, 0.0].max
      recency_multiplier = 0.5**(age_days / half_life_days.to_f)
      base_score * recency_multiplier
    end

    def coerce_time(value)
      return value if value.is_a?(Time)
      return nil if value.nil?

      Time.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def take_by_character_budget(reflections, limit:)
      budget = limit.to_i
      chosen = []

      reflections.each do |reflection|
        line = format_reflection_line(reflection, chosen.size + 1)
        break if budget - line.length < 0

        chosen << reflection
        budget -= line.length + 1
      end

      chosen
    end

    def format_reflection_line(reflection, index)
      created_at = coerce_time(reflection[:created_at] || reflection[:timestamp])
      date_label = created_at ? created_at.strftime("%Y-%m-%d") : "unknown-date"
      score_label = reflection[:score] ? format("%.2f", reflection[:score].to_f) : "n/a"
      text = reflection[:text].to_s.strip
      text = text.gsub(/\s+/, " ")
      "#{index}. [#{date_label}] (score: #{score_label}) #{text}"
    end

    def extract_key_point(reflection)
      text = reflection[:summary].to_s.strip
      text = reflection[:text].to_s.strip if text.empty?
      return nil if text.empty?

      sentence = text.split(/(?<=[.!?])\s+/).first.to_s.strip
      sentence.empty? ? nil : sentence
    end
  end
end