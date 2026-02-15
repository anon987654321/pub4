# frozen_string_literal: true

module MASTER
  # ReflectionMemory - Weighted learning from self-critiques with decay
  class ReflectionMemory
    DECAY_DAYS = 30
    DECAY_FACTOR = 0.4
    HIGH_PRIORITY_THRESHOLD = 0.75
    MAX_CONTEXT_ITEMS = 10

    def initialize(memory = nil)
      @memory = memory || Memory
    end

    def store_reflection(content:, strength:, task_id:, tags: [])
      @memory.remember(
        "#{content} | strength:#{strength} | task:#{task_id} | created:#{Time.now.to_i}",
        :long,
        tags: (tags + [:reflexion]).uniq
      )
    end

    def weighted_reflections(query: nil, limit: MAX_CONTEXT_ITEMS, tags: nil)
      search_tags = tags ? (Array(tags) + [:reflexion]).uniq : [:reflexion]

      raw_reflections = if query
                          @memory.search(query, tags: search_tags, limit: limit * 3)
                        else
                          @memory.recall(tags: search_tags, limit: limit * 3)
                        end

      now = Time.now.to_i

      weighted = raw_reflections.map do |ref|
        created_match = ref.match(/created:(\d+)/)
        created_at = created_match ? created_match[1].to_i : now

        strength_match = ref.match(/strength:([0-9.]+)/)
        strength = strength_match ? strength_match[1].to_f : 0.5

        age_days = (now - created_at) / 86_400.0

        decay_multiplier = age_days > DECAY_DAYS ? DECAY_FACTOR : 1.0
        adjusted_weight = strength * decay_multiplier

        {
          content: ref,
          strength: strength,
          age_days: age_days.round(1),
          decay: decay_multiplier,
          weight: adjusted_weight,
          priority: adjusted_weight >= HIGH_PRIORITY_THRESHOLD ? :high : :normal
        }
      end

      weighted.sort_by { |r| -r[:weight] }.first(limit)
    end

    def build_context_string(query: nil, limit: MAX_CONTEXT_ITEMS)
      reflections = weighted_reflections(query: query, limit: limit)

      high_priority = reflections.select { |r| r[:priority] == :high }
      normal_priority = reflections.select { |r| r[:priority] == :normal }

      parts = []

      if high_priority.any?
        parts << "HIGH PRIORITY LESSONS (strength > #{HIGH_PRIORITY_THRESHOLD}):"
        high_priority.first(4).each do |ref|
          parts << format_reflection(ref)
        end
      end

      if normal_priority.any?
        parts << "\nOTHER REFLECTIONS:"
        normal_priority.first(6).each do |ref|
          parts << format_reflection(ref)
        end
      end

      parts.join("\n")
    end

    def summarize_reflections(limit: 16, llm: nil)
      recent = weighted_reflections(limit: limit)
      return nil if recent.empty? || llm.nil?

      prompt = <<~PROMPT
        Analyze these self-critiques and extract 3 distilled lessons.
        Focus on patterns and actionable insights.

        Recent Reflections:
        #{recent.map { |r| "- [strength: #{r[:strength]}] #{r[:content]}" }.join("\n")}

        Provide 3 concise lessons (1 sentence each):
      PROMPT

      result = llm.ask(prompt, tier: :cheap)
      return nil unless result.ok?

      summary = result.value

      store_reflection(
        content: "DISTILLED: #{summary}",
        strength: 0.9,
        task_id: 'meta',
        tags: %i[distilled_lesson meta]
      )

      summary
    end

    private

    def format_reflection(ref)
      prefix = ref[:priority] == :high ? '  *' : '  -'
      decay_note = ref[:decay] < 1.0 ? " [aged #{ref[:age_days]}d, decayed]" : ''
      "#{prefix} [#{ref[:strength].round(2)}] #{ref[:content]}#{decay_note}"
    end
  end
end
