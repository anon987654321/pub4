# frozen_string_literal: true

module Chamber
  class Creative
    DEFAULT_IDEA_COUNT = 8
    DEFAULT_SCENE_COUNT = 6
    DEFAULT_TURN_COUNT = 10
    DEFAULT_SUMMARY_SENTENCE_COUNT = 5
    DEFAULT_TOP_COMPETITOR_LIMIT = 10
    DEFAULT_COMPETITOR_SAMPLE_LIMIT = 25

    MAX_IDEA_COUNT = 20
    MAX_SCENE_COUNT = 12
    MAX_TURN_COUNT = 20

    ASSOCIATIONS_FOR_COMPETITOR_PRELOAD = %i[products channels campaigns].freeze

    def initialize(llm: nil)
      @llm = llm
    end

    def brainstorm(brief:, options: {})
      config = normalize_options(options)

      idea_count = clamp_count(
        config.fetch(:idea_count, DEFAULT_IDEA_COUNT),
        max: MAX_IDEA_COUNT
      )

      target_audience = config.fetch(:target_audience, nil)
      tone = config.fetch(:tone, nil)
      constraints = Array(config.fetch(:constraints, []))
      key_messages = Array(config.fetch(:key_messages, []))

      return [] if brief.to_s.strip.empty?

      prompt = build_brainstorm_prompt(
        brief: brief,
        idea_count: idea_count,
        target_audience: target_audience,
        tone: tone,
        constraints: constraints,
        key_messages: key_messages
      )

      llm_response = call_llm(prompt, config)
      ideas = parse_bullets(llm_response).first(idea_count)

      ideas.map.with_index(1) do |idea_text, index|
        {
          index: index,
          concept: idea_text,
          rationale: nil,
          hook: extract_hook(idea_text),
          call_to_action: nil
        }
      end
    end

    def video_storyboard(concept:, options: {})
      config = normalize_options(options)

      scene_count = clamp_count(
        config.fetch(:scene_count, DEFAULT_SCENE_COUNT),
        max: MAX_SCENE_COUNT
      )

      format = config.fetch(:format, "short-form")
      aspect_ratio = config.fetch(:aspect_ratio, "9:16")
      platform = config.fetch(:platform, nil)

      return [] if concept.to_s.strip.empty?

      prompt = build_storyboard_prompt(
        concept: concept,
        scene_count: scene_count,
        format: format,
        aspect_ratio: aspect_ratio,
        platform: platform
      )

      llm_response = call_llm(prompt, config)
      raw_scenes = parse_numbered_sections(llm_response).first(scene_count)

      raw_scenes.map.with_index(1) do |scene_text, index|
        {
          scene: index,
          visual: extract_labeled(scene_text, "Visual"),
          audio: extract_labeled(scene_text, "Audio"),
          on_screen_text: extract_labeled(scene_text, "On-screen"),
          notes: extract_labeled(scene_text, "Notes")
        }
      end
    end

    def simulate_conversation(persona:, topic:, options: {})
      config = normalize_options(options)

      turn_count = clamp_count(
        config.fetch(:turn_count, DEFAULT_TURN_COUNT),
        max: MAX_TURN_COUNT
      )

      agent_name = config.fetch(:agent_name, "Guide")
      customer_name = config.fetch(:customer_name, "Customer")
      goal = config.fetch(:goal, nil)

      return [] if persona.to_s.strip.empty? || topic.to_s.strip.empty?

      prompt = build_conversation_prompt(
        persona: persona,
        topic: topic,
        turn_count: turn_count,
        agent_name: agent_name,
        customer_name: customer_name,
        goal: goal
      )

      llm_response = call_llm(prompt, config)
      lines = parse_dialogue_lines(llm_response, agent_name: agent_name, customer_name: customer_name)

      lines.first(turn_count * 2).map.with_index(1) do |line, index|
        speaker, text = line
        { index: index, speaker: speaker, text: text }
      end
    end

    def enhance_prompt(prompt:, context: nil, options: {})
      config = normalize_options(options)

      return "" if prompt.to_s.strip.empty?

      summary_sentence_count = config.fetch(
        :summary_sentence_count,
        DEFAULT_SUMMARY_SENTENCE_COUNT
      )

      style = config.fetch(:style, "clear and specific")
      output_format = config.fetch(:output_format, "prompt")
      constraints = Array(config.fetch(:constraints, []))
      do_not_include = Array(config.fetch(:do_not_include, []))

      enhancement_prompt = build_enhancement_prompt(
        prompt: prompt,
        context: context,
        style: style,
        output_format: output_format,
        summary_sentence_count: summary_sentence_count,
        constraints: constraints,
        do_not_include: do_not_include
      )

      call_llm(enhancement_prompt, config).to_s.strip
    end

    def analyze_competitors(brand:, competitors:, options: {})
      config = normalize_options(options)

      top_limit = clamp_count(
        config.fetch(:top_limit, DEFAULT_TOP_COMPETITOR_LIMIT),
        max: DEFAULT_COMPETITOR_SAMPLE_LIMIT
      )

      competitor_scope = preload_competitor_associations(competitors)
      competitor_records = take_records(competitor_scope, DEFAULT_COMPETITOR_SAMPLE_LIMIT)

      return { brand: brand, competitors: [], summary: nil } if competitor_records.empty?

      prompt = build_competitor_analysis_prompt(
        brand: brand,
        competitors: competitor_records,
        top_limit: top_limit
      )

      llm_response = call_llm(prompt, config)
      bullet_points = parse_bullets(llm_response)

      {
        brand: brand,
        competitors: competitor_records.first(top_limit).map { |record| competitor_snapshot(record) },
        summary: bullet_points.first(top_limit)
      }
    end

    private

    attr_reader :llm

    def normalize_options(options)
      options.is_a?(Hash) ? options : {}
    end

    def clamp_count(value, max:)
      integer_value = value.to_i
      integer_value = 1 if integer_value < 1
      integer_value = max if integer_value > max
      integer_value
    end

    def call_llm(prompt, config)
      return prompt if llm.nil?

      temperature = config.fetch(:temperature, nil)
      model = config.fetch(:model, nil)

      if llm.respond_to?(:call)
        llm.call(prompt: prompt, temperature: temperature, model: model)
      elsif llm.respond_to?(:complete)
        llm.complete(prompt: prompt, temperature: temperature, model: model)
      else
        prompt
      end
    end

    def build_brainstorm_prompt(brief:, idea_count:, target_audience:, tone:, constraints:, key_messages:)
      lines = []
      lines << "Generate #{idea_count} creative campaign ideas."
      lines << "Brief: #{brief.strip}"
      lines << "Target audience: #{target_audience}" if target_audience.to_s.strip != ""
      lines << "Tone: #{tone}" if tone.to_s.strip != ""
      lines << "Key messages: #{key_messages.join('; ')}" if key_messages.any?
      lines << "Constraints: #{constraints.join('; ')}" if constraints.any?
      lines << "Return as bullet points, one idea per line."
      lines.join("\n")
    end

    def build_storyboard_prompt(concept:, scene_count:, format:, aspect_ratio:, platform:)
      lines = []
      lines << "Create a video storyboard with #{scene_count} scenes."
      lines << "Concept: #{concept.strip}"
      lines << "Format: #{format}"
      lines << "Aspect ratio: #{aspect_ratio}"
      lines << "Platform: #{platform}" if platform.to_s.strip != ""
      lines << "For each scene, include:"
      lines << "Visual:, Audio:, On-screen:, Notes:"
      lines << "Return as numbered sections."
      lines.join("\n")
    end

    def build_conversation_prompt(persona:, topic:, turn_count:, agent_name:, customer_name:, goal:)
      lines = []
      lines << "Simulate a helpful conversation with #{turn_count} turns per participant."
      lines << "Persona: #{persona.strip}"
      lines << "Topic: #{topic.strip}"
      lines << "Goal: #{goal}" if goal.to_s.strip != ""
      lines << "Use exactly these speaker labels: #{agent_name}: and #{customer_name}:"
      lines << "Return as alternating dialogue lines."
      lines.join("\n")
    end

    def build_enhancement_prompt(
      prompt:,
      context:,
      style:,
      output_format:,
      summary_sentence_count:,
      constraints:,
      do_not_include:
    )
      lines = []
      lines << "Rewrite the following into a #{style} #{output_format}."
      lines << "Original: #{prompt.strip}"
      lines << "Context: #{context.strip}" if context.to_s.strip != ""
      lines << "Constraints: #{constraints.join('; ')}" if constraints.any?
      lines << "Do not include: #{do_not_include.join('; ')}" if do_not_include.any?
      lines << "Then provide a #{summary_sentence_count}-sentence rationale."
      lines.join("\n")
    end

    def build_competitor_analysis_prompt(brand:, competitors:, top_limit:)
      competitor_names = competitors.map { |record| competitor_display_name(record) }.compact
      lines = []
      lines << "Analyze competitors for brand: #{brand}"
      lines << "Competitors (sample): #{competitor_names.join(', ')}"
      lines << "Provide top #{top_limit} differentiators and opportunities as bullet points."
      lines.join("\n")
    end

    def parse_bullets(text)
      return [] if text.to_s.strip.empty?

      text
        .to_s
        .lines
        .map(&:strip)
        .reject(&:empty?)
        .map { |line| line.sub(/\A[-*•]\s+/, "") }
        .reject(&:empty?)
    end

    def parse_numbered_sections(text)
      return [] if text.to_s.strip.empty?

      sections = []
      current = +""

      text.to_s.lines.each do |line|
        if line.strip.match?(/\A\d+[\).\s]/)
          sections << current.strip unless current.strip.empty?
          current = line.sub(/\A\d+[\).\s]+\s*/, "")
        else
          current << line
        end
      end

      sections << current.strip unless current.strip.empty?
      sections.reject(&:empty?)
    end

    def parse_dialogue_lines(text, agent_name:, customer_name:)
      return [] if text.to_s.strip.empty?

      speakers = [agent_name, customer_name].map { |name| Regexp.escape(name) }.join("|")
      pattern = /\A(#{speakers})\s*:\s*(.+)\z/

      text
        .to_s
        .lines
        .map(&:strip)
        .filter_map do |line|
          match = pattern.match(line)
          match ? [match[1], match[2]] : nil
        end
    end

    def extract_labeled(scene_text, label)
      return nil if scene_text.to_s.strip.empty?

      pattern = /\b#{Regexp.escape(label)}\s*:\s*(.+?)(?:\n[A-Za-z][A-Za-z\s-]*:\s*|\z)/m
      match = pattern.match(scene_text.to_s)
      match ? match[1].to_s.strip.gsub(/\s+/, " ") : nil
    end

    def extract_hook(text)
      return nil if text.to_s.strip.empty?

      match = text.to_s.match(/["“](.+?)["”]/)
      match ? match[1].strip : nil
    end

    def preload_competitor_associations(competitors)
      return competitors unless competitors.respond_to?(:includes)

      competitors.includes(*ASSOCIATIONS_FOR_COMPETITOR_PRELOAD)
    rescue StandardError
      competitors
    end

    def take_records(scope, limit)
      if scope.respond_to?(:limit)
        scope.limit(limit).to_a
      else
        Array(scope).first(limit)
      end
    end

    def competitor_snapshot(record)
      {
        name: competitor_display_name(record),
        website: record.respond_to?(:website) ? record.website : nil,
        category: record.respond_to?(:category) ? record.category : nil
      }
    end

    def competitor_display_name(record)
      return record.name if record.respond_to?(:name) && record.name.to_s.strip != ""
      return record.title if record.respond_to?(:title) && record.title.to_s.strip != ""

      record.to_s
    end
  end
end