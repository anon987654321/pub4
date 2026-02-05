# frozen_string_literal: true

module MASTER
  class CreativeChamber
    # Multi-model deliberation for ideas, conversations, and multimedia
    # LLMs debate concepts, Replicate models generate variations

    LLM_MODELS = {
      sonnet:   'anthropic/claude-sonnet-4',
      grok:     'x-ai/grok-4-fast',
      gemini:   'google/gemini-3-flash-preview',
      deepseek: 'deepseek/deepseek-chat'
    }.freeze

    IMAGE_MODELS = {
      flux:     'black-forest-labs/flux-schnell',
      sdxl:     'stability-ai/sdxl',
      ideogram: 'ideogram-ai/ideogram-v2'
    }.freeze

    VIDEO_MODELS = {
      kling:    'kwaivgi/kling-v2.5-pro',
      minimax:  'minimax/video-01'
    }.freeze

    ARBITER = :sonnet
    MAX_COST = 2.00

    attr_reader :cost, :results

    def initialize(llm, replicate = nil)
      @llm = llm
      @replicate = replicate
      @cost = 0.0
      @results = []
    end

    # Idea brainstorming - multiple models propose and debate
    def brainstorm(topic, participants: [:sonnet, :gpt4, :gemini])
      @results = []

      # Round 1: Each model proposes ideas
      proposals = participants.map do |model|
        next if over_budget?

        response = ask_llm(model, idea_prompt(topic))
        proposal = {
          model: model,
          ideas: response,
          letter: nil
        }
        @results << { type: :proposal, **proposal }
        proposal
      end.compact

      return { ideas: [], cost: @cost } if proposals.empty?

      # Round 2: Each model critiques others and defends their own
      proposals.each_with_index do |prop, i|
        next if over_budget?

        others = proposals.reject.with_index { |_, j| j == i }
        response = ask_llm(prop[:model], debate_prompt(topic, prop, others))
        prop[:letter] = response
        @results << { type: :letter, model: prop[:model], content: response }
      end

      # Arbiter synthesizes best ideas
      synthesis = arbiter_synthesize(topic, proposals)
      { ideas: proposals, synthesis: synthesis, cost: @cost }
    end

    # Image variations - multiple models interpret same prompt
    def image_variations(prompt, models: [:flux, :sdxl])
      return { images: [], cost: @cost } unless @replicate

      images = models.map do |model|
        next if over_budget?

        result = generate_image(model, prompt)
        next unless result

        @results << { type: :image, model: model, url: result[:url] }
        { model: model, url: result[:url], prompt: prompt }
      end.compact

      # LLM describes and compares
      comparison = compare_images(images) if images.size > 1
      { images: images, comparison: comparison, cost: @cost }
    end

    # Video storyboard - LLMs write scenes, models generate
    def video_storyboard(concept, scenes: 3)
      return { scenes: [], cost: @cost } unless @replicate

      # LLMs propose scene breakdowns
      scene_proposals = [:sonnet, :gpt4].map do |model|
        next if over_budget?

        response = ask_llm(model, storyboard_prompt(concept, scenes))
        { model: model, scenes: parse_scenes(response) }
      end.compact

      # Arbiter picks best scene sequence
      final_scenes = arbiter_pick_scenes(concept, scene_proposals)

      # Generate video for each scene
      videos = final_scenes.map.with_index do |scene, i|
        next if over_budget?

        result = generate_video(:kling, scene[:prompt])
        next unless result

        @results << { type: :video, scene: i + 1, url: result[:url] }
        { scene: i + 1, description: scene[:description], url: result[:url] }
      end.compact

      { scenes: videos, cost: @cost }
    end

    # Conversation simulation - models role-play dialogue
    def simulate_conversation(scenario, roles:, turns: 5)
      dialogue = []
      context = scenario

      turns.times do |turn|
        roles.each do |role|
          next if over_budget?

          model = role[:model] || :sonnet
          response = ask_llm(model, dialogue_prompt(context, role, dialogue))

          entry = {
            turn: turn + 1,
            role: role[:name],
            model: model,
            message: response
          }
          dialogue << entry
          @results << { type: :dialogue, **entry }
        end
      end

      # Arbiter summarizes insights from conversation
      summary = ask_llm(ARBITER, summary_prompt(scenario, dialogue))
      { dialogue: dialogue, summary: summary, cost: @cost }
    end

    private

    def ask_llm(model_key, prompt)
      model = LLM_MODELS[model_key]
      return nil unless model

      result = @llm.chat_with_model(model, prompt)
      @cost += @llm.last_cost
      result.ok? ? result.value : nil
    end

    def generate_image(model_key, prompt)
      model = IMAGE_MODELS[model_key]
      return nil unless model && @replicate

      result = @replicate.generate(model, prompt: prompt)
      @cost += result[:cost] if result
      result
    end

    def generate_video(model_key, prompt)
      model = VIDEO_MODELS[model_key]
      return nil unless model && @replicate

      result = @replicate.generate_video(model, prompt: prompt)
      @cost += result[:cost] if result
      result
    end

    def idea_prompt(topic)
      <<~PROMPT
        Topic: #{topic}

        Propose 5 distinct ideas or approaches. For each:
        1. One-line summary
        2. Why it could work (2-3 sentences)
        3. Potential challenges

        Be creative but practical. Sign with your model name.
      PROMPT
    end

    def debate_prompt(topic, my_proposal, others)
      other_ideas = others.map { |o| "#{o[:model]}:\n#{o[:ideas].to_s[0..500]}" }.join("\n\n")

      <<~PROMPT
        Topic: #{topic}

        Your original ideas:
        #{my_proposal[:ideas].to_s[0..600]}

        Other models proposed:
        #{other_ideas}

        Write a brief letter (4-6 sentences):
        1. Defend your strongest idea
        2. Acknowledge one good idea from others
        3. Identify one risky idea and why
        4. Suggest a synthesis combining best elements

        Sign with your model name.
      PROMPT
    end

    def arbiter_synthesize(topic, proposals)
      return nil if over_budget?

      summary = proposals.map do |p|
        "#{p[:model]}:\nIdeas: #{p[:ideas].to_s[0..400]}\nLetter: #{p[:letter].to_s[0..300]}"
      end.join("\n\n---\n\n")

      prompt = <<~PROMPT
        Topic: #{topic}

        Multiple models proposed and debated:
        #{summary}

        As arbiter, synthesize the BEST ideas into a coherent plan:
        1. Top 3 ideas to pursue (with attribution)
        2. Key insights from the debate
        3. Recommended next steps

        Be decisive. Credit good ideas by model name.
      PROMPT

      ask_llm(ARBITER, prompt)
    end

    def storyboard_prompt(concept, scene_count)
      <<~PROMPT
        Create a #{scene_count}-scene storyboard for: #{concept}

        For each scene, provide:
        ## SCENE N
        **Description:** What happens (1-2 sentences)
        **Visual:** Camera angle, lighting, mood
        **Prompt:** Video generation prompt (20-40 words, cinematic style)

        Focus on visual storytelling. Each scene should flow naturally to the next.
      PROMPT
    end

    def parse_scenes(response)
      return [] unless response

      scenes = []
      response.scan(/## SCENE (\d+)(.*?)(?=## SCENE|\z)/mi) do |num, content|
        desc = content.match(/\*\*Description:\*\*\s*(.+?)(?=\*\*|$)/mi)&.[](1)&.strip
        prompt = content.match(/\*\*Prompt:\*\*\s*(.+?)(?=\*\*|$)/mi)&.[](1)&.strip
        scenes << { scene: num.to_i, description: desc, prompt: prompt } if prompt
      end
      scenes
    end

    def arbiter_pick_scenes(concept, proposals)
      return [] if proposals.empty? || over_budget?

      all_scenes = proposals.flat_map { |p| p[:scenes].map { |s| s.merge(model: p[:model]) } }
      return proposals.first[:scenes] if proposals.size == 1

      summary = proposals.map { |p| "#{p[:model]}:\n#{p[:scenes].map { |s| "- #{s[:description]}" }.join("\n")}" }.join("\n\n")

      prompt = <<~PROMPT
        Concept: #{concept}

        Two models proposed storyboards:
        #{summary}

        Pick the BEST scene sequence (can mix from both).
        Return the winning scenes in order with their prompts.
      PROMPT

      response = ask_llm(ARBITER, prompt)
      parse_scenes(response).presence || proposals.first&.dig(:scenes) || []
    end

    def dialogue_prompt(scenario, role, history)
      recent = history.last(6).map { |h| "#{h[:role]}: #{h[:message].to_s[0..200]}" }.join("\n")

      <<~PROMPT
        Scenario: #{scenario}

        You are: #{role[:name]}
        Your perspective: #{role[:perspective]}
        Your goal: #{role[:goal]}

        Recent dialogue:
        #{recent}

        Respond in character (2-4 sentences). Be authentic to your role.
        Advance the conversation meaningfully.
      PROMPT
    end

    def summary_prompt(scenario, dialogue)
      transcript = dialogue.map { |d| "#{d[:role]}: #{d[:message].to_s[0..150]}" }.join("\n")

      <<~PROMPT
        Scenario: #{scenario}

        Dialogue transcript:
        #{transcript}

        Summarize:
        1. Key points of agreement
        2. Unresolved tensions
        3. Surprising insights
        4. Recommended resolution

        Be concise (5-7 sentences).
      PROMPT
    end

    def compare_images(images)
      return nil if images.empty? || over_budget?

      prompt = <<~PROMPT
        Compare these #{images.size} AI-generated images for the prompt:
        "#{images.first[:prompt]}"

        Models used: #{images.map { |i| i[:model] }.join(', ')}

        Without seeing them directly, describe what differences you'd expect:
        1. Style characteristics of each model
        2. Typical strengths/weaknesses
        3. Which would likely be best for this prompt and why
      PROMPT

      ask_llm(ARBITER, prompt)
    end

    def over_budget?
      @cost >= MAX_COST
    end
  end
end
