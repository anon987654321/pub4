# frozen_string_literal: true

module MASTER
  # CreativeChamber - Multi-model deliberation for CREATIVE IDEATION
  # Generates ideas/conversations, scores them, then generates multimedia via Replicate
  #
  # NOTE: One of four deliberation/generation engines:
  #   - Chamber: Code refinement via multi-model debate
  #   - CreativeChamber (this file): Creative ideation for concepts/multimedia
  #   - Council: Opinion/judgment deliberation with fixed member roles
  #   - Swarm: Generate many variations, curate best via scoring
  class CreativeChamber
    # Multi-model deliberation for ideas, conversations, and multimedia
    # LLMs debate concepts, Replicate models generate variations

    # String slice limits
    MAX_IDEA_PREVIEW = 500
    MAX_PROPOSAL_PREVIEW = 600
    MAX_DIALOGUE_PREVIEW = 400
    MAX_LETTER_PREVIEW = 300
    MAX_HISTORY_PREVIEW = 200
    MAX_TRANSCRIPT_PREVIEW = 150
    MAX_CODE_PREVIEW = 4000
    MAX_FEATURE_DESC = 100
    MAX_DETAIL_PREVIEW = 200
    MAX_IDEA_DESC = 150

    LLM_MODELS = {
      sonnet:   'anthropic/claude-sonnet-4',
      grok:     'x-ai/grok-4-fast',
      gemini:   'google/gemini-3-flash-preview',
      deepseek: 'deepseek/deepseek-chat',
      kimi:     'moonshotai/kimi-k2.5'
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
      other_ideas = others.map { |o| "#{o[:model]}:\n#{o[:ideas].to_s[0..MAX_IDEA_PREVIEW]}" }.join("\n\n")

      <<~PROMPT
        Topic: #{topic}

        Your original ideas:
        #{my_proposal[:ideas].to_s[0..MAX_PROPOSAL_PREVIEW]}

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
        "#{p[:model]}:\nIdeas: #{p[:ideas].to_s[0..MAX_DIALOGUE_PREVIEW]}\nLetter: #{p[:letter].to_s[0..MAX_LETTER_PREVIEW]}"
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
      recent = history.last(6).map { |h| "#{h[:role]}: #{h[:message].to_s[0..MAX_HISTORY_PREVIEW]}" }.join("\n")

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
      transcript = dialogue.map { |d| "#{d[:role]}: #{d[:message].to_s[0..MAX_TRANSCRIPT_PREVIEW]}" }.join("\n")

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

    public

    # Prompt enhancement - models refine a prompt through deliberation
    def enhance_prompt(raw_prompt, purpose: :general, rounds: 2)
      @results = []
      current = raw_prompt

      rounds.times do |round|
        # Each model proposes an enhanced version
        proposals = [:grok, :gemini, :deepseek, :kimi].map do |model|
          next if over_budget?

          response = ask_llm(model, enhance_prompt_prompt(current, purpose, round + 1))
          next unless response

          enhanced = extract_enhanced_prompt(response)
          proposal = {
            model: model,
            round: round + 1,
            enhanced: enhanced,
            reasoning: response
          }
          @results << { type: :enhancement, **proposal }
          proposal
        end.compact

        break if proposals.empty?

        # Arbiter picks best or synthesizes
        best = arbiter_pick_enhancement(current, proposals, purpose)
        current = best if best && !best.empty?
      end

      { original: raw_prompt, enhanced: current, history: @results, cost: @cost }
    end

    private

    def enhance_prompt_prompt(prompt, purpose, round)
      purpose_hints = case purpose
                      when :image then "Focus on visual details, style, lighting, composition, mood."
                      when :code then "Focus on specificity, constraints, expected behavior, edge cases."
                      when :creative then "Focus on tone, audience, format, originality."
                      else "Focus on clarity, specificity, and actionability."
                      end

      <<~PROMPT
        TASK: Enhance this prompt (round #{round})

        ORIGINAL PROMPT:
        #{prompt}

        PURPOSE: #{purpose}
        #{purpose_hints}

        RULES:
        - Make it more specific and effective
        - Add missing context the AI needs
        - Remove ambiguity
        - Keep the core intent intact
        - Don't make it unnecessarily longer

        Return your enhanced prompt wrapped in <enhanced> tags.
        Then briefly explain your changes (2-3 sentences).
      PROMPT
    end

    def extract_enhanced_prompt(response)
      return nil unless response

      if response =~ /<enhanced>(.*?)<\/enhanced>/mi
        $1.strip
      else
        # Fallback: take first paragraph if no tags
        response.split("\n\n").first&.strip
      end
    end

    def arbiter_pick_enhancement(original, proposals, purpose)
      return proposals.first&.dig(:enhanced) if proposals.size == 1
      return nil if over_budget?

      summary = proposals.map do |p|
        "#{p[:model]}:\n#{p[:enhanced]}"
      end.join("\n\n---\n\n")

      prompt = <<~PROMPT
        ORIGINAL PROMPT: #{original}
        PURPOSE: #{purpose}

        Multiple models proposed enhanced versions:
        #{summary}

        Pick the BEST enhanced prompt or synthesize the best elements.
        Return ONLY the final prompt wrapped in <enhanced> tags.
      PROMPT

      response = ask_llm(ARBITER, prompt)
      extract_enhanced_prompt(response)
    end

    public

    # Competitor analysis - identify top features from similar projects
    def analyze_competitors(domain, competitors: [], user_code: nil)
      @results = []

      # Each model researches the competitive landscape
      research = [:grok, :gemini, :kimi].map do |model|
        next if over_budget?

        response = ask_llm(model, competitor_research_prompt(domain, competitors))
        next unless response

        features = parse_features(response)
        result = { model: model, features: features, raw: response }
        @results << { type: :competitor_research, **result }
        result
      end.compact

      return { features: [], gaps: [], cost: @cost } if research.empty?

      # Arbiter consolidates feature list
      all_features = arbiter_consolidate_features(domain, research)

      # If user code provided, identify gaps
      gaps = []
      if user_code && !over_budget?
        gaps = identify_gaps(domain, all_features, user_code)
      end

      {
        domain: domain,
        top_features: all_features,
        gaps: gaps,
        research: research,
        cost: @cost
      }
    end

    # Gap analysis - compare code against best practices
    def identify_gaps(domain, features, user_code)
      return [] if over_budget?

      code_sample = user_code.is_a?(String) ? user_code : File.read(user_code) rescue ""
      code_sample = code_sample[0..MAX_CODE_PREVIEW]

      prompt = <<~PROMPT
        DOMAIN: #{domain}

        TOP FEATURES competitors have:
        #{features.map.with_index { |f, i| "#{i + 1}. #{f}" }.join("\n")}

        USER'S CODE:
        ```
        #{code_sample}
        ```

        Analyze which features are MISSING or WEAK in this code.
        For each gap:
        - Feature name
        - Why it matters
        - How hard to implement (easy/medium/hard)
        - Suggested approach (1 sentence)

        Be specific. Only list genuine gaps, not style preferences.
      PROMPT

      response = ask_llm(ARBITER, prompt)
      parse_gaps(response)
    end

    # Feature ideation - generate new feature ideas based on domain
    def ideate_features(domain, existing_features: [], constraints: [])
      @results = []

      # Each model proposes features
      proposals = [:sonnet, :grok, :gemini, :kimi].map do |model|
        next if over_budget?

        response = ask_llm(model, feature_ideation_prompt(domain, existing_features, constraints))
        next unless response

        features = parse_feature_ideas(response)
        result = { model: model, features: features, raw: response }
        @results << { type: :feature_idea, **result }
        result
      end.compact

      return { features: [], cost: @cost } if proposals.empty?

      # Arbiter ranks and synthesizes
      ranked = arbiter_rank_features(domain, proposals)

      {
        domain: domain,
        top_features: ranked,
        all_proposals: proposals,
        cost: @cost
      }
    end

    private

    def competitor_research_prompt(domain, competitors)
      comp_list = competitors.empty? ? "Research the top 5 competitors in this space." : "Focus on: #{competitors.join(', ')}"

      <<~PROMPT
        DOMAIN: #{domain}
        #{comp_list}

        Identify the TOP 10 features that successful products in this domain have.
        For each feature:
        - Name (2-4 words)
        - What it does (1 sentence)
        - Why users love it (1 sentence)

        Focus on features that differentiate winners from losers.
        Be specific, not generic (e.g., "real-time collaboration" not "good UX").
      PROMPT
    end

    def parse_features(response)
      return [] unless response

      features = []
      response.scan(/(?:^|\n)\s*[-\d.]*\s*\*?\*?([A-Z][^:\n]{2,40})[:*]?\*?\s*[-–]?\s*(.+?)(?=\n|$)/i) do |name, desc|
        features << "#{name.strip}: #{desc.strip[0..MAX_FEATURE_DESC]}"
      end

      # Fallback: just extract lines that look like features
      if features.empty?
        response.lines.each do |line|
          line = line.strip
          next if line.empty? || line.length < 10 || line.length > 150
          features << line if line =~ /^[-\d.*]\s*.+/
        end
      end

      features.first(15)
    end

    def arbiter_consolidate_features(domain, research)
      return [] if over_budget?

      all = research.flat_map { |r| r[:features] }.uniq
      return all.first(10) if all.size <= 10

      prompt = <<~PROMPT
        DOMAIN: #{domain}

        Multiple models identified these competitor features:
        #{all.map.with_index { |f, i| "#{i + 1}. #{f}" }.join("\n")}

        Consolidate into the TOP 10 most important features.
        Remove duplicates, merge similar ones.
        Rank by importance to users.

        Return numbered list, one feature per line.
      PROMPT

      response = ask_llm(ARBITER, prompt)
      parse_numbered_list(response).first(10)
    end

    def parse_gaps(response)
      return [] unless response

      gaps = []
      # Look for structured gap descriptions
      response.scan(/(?:^|\n)\s*[-\d.]*\s*\*?\*?([^:\n]{3,50})[:*]?\*?\s*(.*?)(?=\n[-\d.*]|\n\n|\z)/mi) do |name, details|
        next if name.strip.length < 3
        gaps << {
          feature: name.strip,
          details: details.strip[0..MAX_DETAIL_PREVIEW],
          priority: details =~ /hard/i ? :high : (details =~ /medium/i ? :medium : :low)
        }
      end

      gaps.first(10)
    end

    def feature_ideation_prompt(domain, existing, constraints)
      existing_text = existing.empty? ? "None specified" : existing.join(", ")
      constraints_text = constraints.empty? ? "None" : constraints.join(", ")

      <<~PROMPT
        DOMAIN: #{domain}
        EXISTING FEATURES: #{existing_text}
        CONSTRAINTS: #{constraints_text}

        Propose 5 NEW feature ideas that would make this product stand out.
        For each feature:
        - **Name**: Catchy 2-4 word name
        - **What**: What it does (1-2 sentences)
        - **Why**: Why users would love it
        - **Effort**: Low/Medium/High to implement

        Be creative but practical. Avoid obvious ideas.
        Think about what competitors DON'T have yet.
      PROMPT
    end

    def parse_feature_ideas(response)
      return [] unless response

      ideas = []
      response.scan(/\*\*Name\*\*:?\s*(.+?)(?:\n|$).*?\*\*What\*\*:?\s*(.+?)(?:\n|$)/mi) do |name, what|
        ideas << { name: name.strip, description: what.strip[0..MAX_IDEA_DESC] }
      end

      # Fallback: look for numbered items
      if ideas.empty?
        response.scan(/(?:^|\n)\s*\d+[.)]\s*\*?\*?([^:\n*]+)\*?\*?:?\s*(.+?)(?=\n\d|\n\n|\z)/mi) do |name, desc|
          ideas << { name: name.strip, description: desc.strip[0..MAX_IDEA_DESC] }
        end
      end

      ideas.first(10)
    end

    def arbiter_rank_features(domain, proposals)
      return [] if over_budget?

      all = proposals.flat_map { |p| p[:features] }
      return all.first(5) if all.size <= 5

      summary = proposals.map do |p|
        features = p[:features].map { |f| "- #{f[:name]}: #{f[:description]}" }.join("\n")
        "#{p[:model]}:\n#{features}"
      end.join("\n\n")

      prompt = <<~PROMPT
        DOMAIN: #{domain}

        Multiple models proposed features:
        #{summary}

        Rank the TOP 5 most valuable and feasible features.
        Consider: user impact, uniqueness, implementation effort.

        Return as numbered list with brief reasoning.
      PROMPT

      response = ask_llm(ARBITER, prompt)
      parse_numbered_list(response).first(5).map { |text| { name: text.split(':').first, description: text } }
    end

    def parse_numbered_list(response)
      return [] unless response

      items = []
      response.lines.each do |line|
        line = line.strip
        if line =~ /^\d+[.)]\s*(.+)/
          items << $1.strip
        end
      end
      items
    end
  end
end
