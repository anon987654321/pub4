# frozen_string_literal: true

require 'singleton'

module MASTER
  # Chamber - Consolidated Deliberation Engine with Strategy Pattern
  #
  # This file consolidates FOUR deliberation/generation engines:
  # 1. Chamber: Code refinement via multi-model debate (original functionality)
  # 2. CreativeChamber: Creative ideation for concepts/multimedia
  # 3. Council: Opinion/judgment deliberation with fixed member roles
  # 4. Swarm: Generate many variations, curate best via scoring
  #
  # Each engine uses a different strategy for multi-model collaboration:
  # - Chamber: Diff-based code improvements with proposal/rebuttal rounds
  # - CreativeChamber: Brainstorming, multimedia generation, prompt enhancement
  # - Council: Fixed-role debate with echo chamber memory and synthesis
  # - Swarm: Mass generation with quality-based curation
  #
  class Chamber

    MODELS = {
      sonnet:   'anthropic/claude-sonnet-4',
      grok:     'x-ai/grok-4-fast',
      gemini:   'google/gemini-3-flash-preview',
      deepseek: 'deepseek/deepseek-chat',
      glm:      'z-ai/glm-4.7',
      kimi:     'moonshotai/kimi-k2.5'
    }.freeze

    ARBITER = :sonnet
    MAX_ROUNDS = 3
    MAX_COST_PER_FILE = 0.50
    CONSENSUS_THRESHOLD = 0.6  # Need >60% agreement
    CODE_PREVIEW_LIMIT = 5000
    LETTER_PREVIEW_LIMIT = 400
    DIFF_PREVIEW_LIMIT = 600
    REBUTTAL_PREVIEW_LIMIT = 150
    SUMMARY_LETTER_LIMIT = 300
    SUMMARY_DIFF_LIMIT = 500

    attr_reader :cost, :rounds, :proposals

    def initialize(llm)
      @llm = llm
      @cost = 0.0
      @rounds = 0
      @proposals = []
    end

    def deliberate(code, filename: 'code', participants: [:sonnet, :gemini, :deepseek])
      @proposals = []
      @rounds = 0

      # Round 1: Each participant proposes diff + letter
      participants.each do |model|
        next if over_budget?

        response = ask_model(model, proposal_prompt(code, filename))
        proposal = parse_proposal(response, model)
        @proposals << proposal if proposal
      end

      return { code: code, proposals: [], cost: @cost } if @proposals.empty?

      # Round 2-N: Models review each other's proposals
      MAX_ROUNDS.times do |round|
        @rounds = round + 1
        break if over_budget?

        # Each model reviews and responds to others
        @proposals.each_with_index do |prop, i|
          next if over_budget?

          others = @proposals.reject.with_index { |_, j| j == i }
          response = ask_model(
            prop[:model],
            review_prompt(code, others, filename)
          )
          rebuttal = parse_rebuttal(response, prop[:model])
          prop[:rebuttals] ||= []
          prop[:rebuttals] << rebuttal if rebuttal
        end

        break if consensus_reached?
      end

      # Arbiter reviews all proposals and cherry-picks
      final = arbiter_decide(code, filename)
      { code: final, proposals: @proposals, cost: @cost, rounds: @rounds }
    end

    private

    def ask_model(model_key, prompt)
      model = MODELS[model_key]
      return nil unless model

      result = @llm.chat_with_model(model, prompt)
      @cost += @llm.last_cost
      result.ok? ? result.value : nil
    end

    def proposal_prompt(code, filename)
      <<~PROMPT
        You are reviewing code for improvement. Respond in TWO parts:

        ## PART 1: DIFF
        Propose changes as a unified diff. Use this format:
        ```diff
        @@ -line,count +line,count @@
        -old line
        +new line
        ```
        Only include lines you're changing (with 2 lines context).
        Maximum 5 changes.

        ## PART 2: LETTER
        Write a brief letter (3-5 sentences) to the original author:
        - What you're improving and why
        - The principle or best practice behind each change
        - Any trade-offs the author should consider

        Sign with your model name.

        ---
        FILE: #{filename}
        ```
        #{code[0..CODE_PREVIEW_LIMIT]}
        ```
      PROMPT
    end

    def review_prompt(code, other_proposals, filename)
      summaries = other_proposals.map do |p|
        "### #{p[:model]}\n#{p[:letter].to_s[0..LETTER_PREVIEW_LIMIT]}\n```diff\n#{p[:diff].to_s[0..DIFF_PREVIEW_LIMIT]}\n```"
      end.join("\n\n")

      <<~PROMPT
        Other reviewers proposed these changes to #{filename}:

        #{summaries}

        Write a brief REBUTTAL (3-4 sentences):
        1. Which proposals you support (and why)
        2. Which you oppose (and why)
        3. Any concerns about their changes

        Be collegial but honest. Sign with your model name.
      PROMPT
    end

    def parse_proposal(response, model)
      return nil unless response

      diff = extract_section(response, 'diff')
      letter = extract_section(response, 'letter') || extract_after(response, '## PART 2')

      {
        model: model,
        diff: diff,
        letter: letter,
        rebuttals: []
      }
    end

    def parse_rebuttal(response, model)
      return nil unless response
      { model: model, content: response.strip }
    end

    def extract_section(text, type)
      case type
      when 'diff'
        text.match(/```diff\n(.*?)```/m)&.[](1)&.strip
      when 'letter'
        text.match(/## PART 2.*?\n(.*?)(?:\n##|\z)/m)&.[](1)&.strip
      end
    end

    def extract_after(text, marker)
      idx = text.index(marker)
      return nil unless idx
      text[(idx + marker.length)..].strip
    end

    def arbiter_decide(original, filename)
      return original if @proposals.empty? || over_budget?

      tie_detected = detect_tie?

      summary = @proposals.map do |p|
        rebuttals = p[:rebuttals]&.map { |r| "  - #{r[:model]}: #{r[:content].to_s[0..REBUTTAL_PREVIEW_LIMIT]}" }&.join("\n")
        <<~ENTRY
          ### #{p[:model]}
          **Letter:** #{p[:letter].to_s[0..SUMMARY_LETTER_LIMIT]}
          **Diff:**
          ```diff
          #{p[:diff].to_s[0..SUMMARY_DIFF_LIMIT]}
          ```
          **Rebuttals:**
          #{rebuttals}
        ENTRY
      end.join("\n")

      tie_note = tie_detected ? 
        "\nNOTE: Models are divided. Be conservative—only accept uncontested improvements." : ""

      prompt = <<~PROMPT
        You are the ARBITER. Review all proposals for #{filename}:

        #{summary}#{tie_note}

        Your task:
        1. Evaluate each proposed change
        2. Accept changes that are clearly improvements
        3. Reject changes that are risky, contested, or unnecessary
        4. Apply accepted changes to the original code

        Return:
        ## ACCEPTED CHANGES
        List which changes you're accepting and why (one line each)

        ## REJECTED CHANGES
        List rejected and why (one line each)

        ## FINAL CODE
        ```
        [the improved code with accepted changes applied]
        ```
      PROMPT

      result = ask_model(ARBITER, prompt)
      extract_final_code(result) || original
    end

    def extract_final_code(response)
      return nil unless response

      # Look for code block after "FINAL CODE"
      if response =~ /## FINAL CODE.*?```\w*\n(.*?)```/m
        $1.strip
      elsif response =~ /```\w*\n(.*?)```/m
        $1.strip
      end
    end

    def consensus_reached?
      return true if @proposals.size < 2

      # Count support/oppose signals in rebuttals
      supports = 0
      opposes = 0
      
      @proposals.each do |p|
        (p[:rebuttals] || []).each do |r|
          text = r[:content].to_s.downcase
          supports += 1 if text.match?(/\b(agree|support|approve|accept)\b/)
          opposes += 1 if text.match?(/\b(disagree|oppose|reject|concern)\b/)
        end
      end

      total = supports + opposes
      return false if total == 0

      supports.to_f / total > CONSENSUS_THRESHOLD
    end

    def detect_tie?
      return false if @proposals.size < 2

      # Count how many rebuttals oppose each proposal
      opposition_counts = @proposals.map do |p|
        (p[:rebuttals] || []).count { |c| c[:content].to_s.downcase.match?(/\b(disagree|oppose|reject)\b/) }
      end

      # Tie if multiple proposals have similar opposition
      max_opp = opposition_counts.max || 0
      opposition_counts.count { |c| c == max_opp } > 1
    end

    def over_budget?
      @cost >= MAX_COST_PER_FILE
    end
  end

  # ========================================================================
  # CREATIVE CHAMBER - Multi-model deliberation for CREATIVE IDEATION
  # ========================================================================
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

    def over_budget?
      @cost >= MAX_COST
    end
  end

  # ========================================================================
  # COUNCIL - Multi-provider deliberation with FIXED MEMBER ROLES
  # ========================================================================
  module Council
    class << self
      MEMBERS = {
        claude: {
          provider: :anthropic,
          model: 'claude-3-5-sonnet-20241022',
          role: :philosopher,
          strengths: [:reasoning, :safety, :nuance]
        },
        grok: {
          provider: :xai,
          model: 'grok-2-1212',
          role: :rebel,
          strengths: [:creativity, :humor, :edge_cases]
        },
        kimi: {
          provider: :moonshot,
          model: 'moonshot-v1-32k',
          role: :analyst,
          strengths: [:structured, :thorough, :chinese_context]
        },
        gemini: {
          provider: :google,
          model: 'gemini-2.0-flash-exp',
          role: :generalist,
          strengths: [:speed, :broad_knowledge, :multimodal]
        }
      }.freeze

      def debate(prompt:, members: [:claude, :grok, :kimi], rounds: 2, store: true)
        echo = EchoChamber.instance
        history = []
        
        puts "council: #{members.size} members, #{rounds} rounds"
        
        # Round 1: Independent
        responses = members.map do |m|
          print "  #{m}..."
          echoes = echo.find_similar(prompt, limit: 3, exclude: m)
          enhanced = echoes.any? ? "#{prompt}\n\nPast insights:\n#{echoes.map{|e| e[:content][0..100]}.join("\n")}" : prompt
          resp = call_llm(m, enhanced)
          puts " ✓"
          history << {member: m, round: 1, content: resp}
          echo.store(content: resp, source: m, prompt: prompt, tags: [:debate, MEMBERS[m][:role]]) if store
          {member: m, response: resp, role: MEMBERS[m][:role]}
        end
        
        # Round 2+: Synthesis
        (2..rounds).each do |r|
          responses = members.map do |m|
            others = responses.reject{|x| x[:member] == m}.map{|o| "#{o[:member]}: #{o[:response]}"}.join("\n\n")
            synthesis = "Original: #{prompt}\n\nOthers said:\n#{others}\n\nYour synthesis:"
            resp = call_llm(m, synthesis)
            history << {member: m, round: r, content: resp}
            echo.store(content: resp, source: m, prompt: prompt, tags: [:synthesis, r]) if store
            {member: m, response: resp, role: MEMBERS[m][:role]}
          end
        end
        
        # Consensus
        consensus_prompt = "Council perspectives:\n#{responses.map{|r| "#{r[:member]}: #{r[:response]}"}.join("\n\n")}\n\nProvide JSON: {\"synthesis\": \"...\", \"confidence\": 0.85}"
        consensus_raw = MASTER::LLM.call(consensus_prompt, model: 'smart')
        
        consensus = begin
          JSON.parse(consensus_raw.match(/\{.*\}/m)[0], symbolize_names: true)
        rescue
          {synthesis: consensus_raw, confidence: 0.7}
        end
        
        echo.store(content: consensus[:synthesis], source: :consensus, prompt: prompt, tags: [:consensus], strength: consensus[:confidence]) if store && consensus[:confidence] > 0.75
        
        {consensus: consensus, perspectives: responses, history: history, echo_size: echo.size}
      end
      
      def quick_check(prompt:, members: [:claude, :grok])
        debate(prompt: prompt, members: members, rounds: 1, store: false)
      end
      
      def dream_session(topic:, duration_minutes: 10)
        start = Time.now
        reflections = []
        
        puts "dream: #{topic} (#{duration_minutes}m)"
        
        iteration = 0
        while Time.now - start < duration_minutes * 60
          iteration += 1
          members = MEMBERS.keys.sample(2)
          prompt = reflections.empty? ? "Explore #{topic} from unexpected angle" : "Building on: #{reflections.last[:insight][0..80]}... Next layer?"
          
          print "  [#{iteration}] #{members.join('+')}..."
          result = debate(prompt: prompt, members: members, rounds: 1, store: true)
          reflections << {iteration: iteration, members: members, insight: result[:consensus][:synthesis]}
          
          sleep 30
        end
        
        puts " ✓ #{reflections.size} insights"
        {topic: topic, duration: Time.now - start, iterations: reflections.size, reflections: reflections}
      end
      
      def emergency_consult(prompt:, previous_attempts:)
        puts "emergency: low confidence consult"
        context = "Previous attempts:\n#{previous_attempts.map.with_index{|a,i| "#{i+1}: #{a[:response][0..100]}"}.join("\n")}\n\nTask: #{prompt}"
        debate(prompt: context, members: [:claude, :grok, :kimi], rounds: 2, store: true)
      end
      
      private
      
      def call_llm(member, prompt)
        config = MEMBERS[member]
        case config[:provider]
        when :anthropic then MASTER::LLM.anthropic(prompt, model: config[:model])
        when :xai then MASTER::LLM.xai(prompt, model: config[:model])
        when :moonshot then MASTER::LLM.moonshot(prompt, model: config[:model])
        when :google then MASTER::LLM.google(prompt, model: config[:model])
        else MASTER::LLM.call(prompt, model: 'smart')
        end
      rescue => e
        "[Error from #{member}: #{e.message}]"
      end
    end
    
    class EchoChamber
      include Singleton
      
      def initialize
        @storage = []
        @embeddings = {}
      end
      
      def store(content:, source:, prompt:, tags:, strength: 0.7)
        emb = embed(content)
        @storage << {content: content, source: source, prompt: prompt, tags: Array(tags), strength: strength, embedding: emb, timestamp: Time.now}
      end
      
      def find_similar(query, limit: 5, exclude: nil)
        q_emb = embed(query)
        candidates = exclude ? @storage.reject{|s| s[:source] == exclude} : @storage
        
        scored = candidates.map do |item|
          age_days = (Time.now - item[:timestamp]) / 86400.0
          decay = [0.4 ** (age_days / 30.0), 0.1].max
          sim = cosine_sim(q_emb, item[:embedding])
          item.merge(similarity: sim * decay * item[:strength])
        end
        
        scored.sort_by{|x| -x[:similarity]}.take(limit)
      end
      
      def cluster_by_topic(topic)
        relevant = @storage.select{|s| s[:prompt].include?(topic) || s[:content].include?(topic)}
        relevant.group_by{|r| r[:tags].first}.map{|tag, items| {tag: tag, count: items.size, sample: items.first[:content][0..150]}}
      end
      
      def size
        @storage.size
      end
      
      def stats
        {total: @storage.size, by_source: @storage.group_by{|s| s[:source]}.transform_values(&:count)}
      end
      
      private
      
      def embed(text)
        @embeddings[text] ||= begin
          chars = text.downcase.chars.map(&:ord)
          (0..127).map{|i| chars.count(i+32) / [text.length, 1].max.to_f}
        end
      end
      
      def cosine_sim(a, b)
        dot = a.zip(b).map{|x,y| x*y}.sum
        mag_a = Math.sqrt(a.map{|x| x**2}.sum)
        mag_b = Math.sqrt(b.map{|x| x**2}.sum)
        dot / (mag_a * mag_b + 1e-10)
      end
    end
  end

  # ========================================================================
  # SWARM - Generate many alternatives, curate to the best
  # ========================================================================
  module Swarm
    OUTPUT_DIR = File.join(MASTER::ROOT, 'var', 'swarm')

    # Default generation parameters
    DEFAULTS = {
      count: 64,           # Generate this many variations
      keep: 8,             # Keep only the best
      parallel: 4,         # Concurrent generations
      score_threshold: 0.7 # Minimum quality score to consider
    }.freeze

    # Variation strategies for different content types
    STRATEGIES = {
      image: {
        vary_prompt: true,
        vary_seed: true,
        vary_model: true,
        vary_chain: true,
        vary_guidance: true,
        models: %i[flux_schnell flux_dev sdxl ideogram recraft],
        chains: %i[blockbuster halation neon_noir golden_hour vintage_cinema],
        guidance_range: (5.0..15.0)
      },
      video: {
        vary_prompt: true,
        vary_seed: true,
        vary_model: true,
        vary_duration: false,
        models: %i[hailuo kling luma_ray wan],
        durations: [5, 10]
      },
      audio: {
        vary_prompt: true,
        vary_seed: true,
        vary_model: true,
        models: %i[musicgen riffusion bark],
        durations: [10, 15, 30]
      },
      postpro: {
        vary_preset: true,
        vary_stock: true,
        vary_lens: true,
        vary_intensity: true,
        presets: %i[portrait blockbuster street dream neon_night horror golden_age indie],
        intensity_range: (0.5..1.2)
      }
    }.freeze

    # Quality criteria for ranking
    QUALITY_CRITERIA = {
      aesthetic: {
        weight: 0.3,
        prompt: 'Rate the aesthetic quality of this image from 0 to 10. Consider composition, color harmony, visual appeal.'
      },
      technical: {
        weight: 0.25,
        prompt: 'Rate the technical quality from 0 to 10. Consider sharpness, exposure, noise, artifacts.'
      },
      originality: {
        weight: 0.25,
        prompt: 'Rate the originality from 0 to 10. How unique and creative is this image?'
      },
      emotional: {
        weight: 0.2,
        prompt: 'Rate the emotional impact from 0 to 10. Does this image evoke a strong feeling?'
      }
    }.freeze

    class << self
      # Generate many variations and curate to the best
      def generate(prompt, type: :image, count: nil, keep: nil, strategy: nil)
        FileUtils.mkdir_p(OUTPUT_DIR)

        config = STRATEGIES[type] || STRATEGIES[:image]
        count ||= DEFAULTS[:count]
        keep ||= DEFAULTS[:keep]

        session_id = Time.now.strftime('%Y%m%d_%H%M%S')
        session_dir = File.join(OUTPUT_DIR, session_id)
        FileUtils.mkdir_p(session_dir)

        puts "swarm: #{count} #{type}"
        puts "  prompt: #{prompt[0..50]}..."
        puts "  session: #{session_id}"

        # Phase 1: Generate all variations
        variations = generate_variations(prompt, type, config, count, session_dir)

        puts "  #{variations.size} generated, scoring..."

        # Phase 2: Score each variation
        scored = score_variations(variations, type)

        # Phase 3: Rank and select top candidates
        ranked = scored.sort_by { |v| -v[:score] }
        selected = ranked.first(keep)
        rejected = ranked[keep..]

        # Phase 4: Organize output
        organize_output(session_dir, selected, rejected)

        # Summary
        puts "  ✓ #{selected.size}/#{variations.size} selected (≥#{selected.last&.dig(:score)&.round(2)})"

        Result.ok({
          session: session_id,
          generated: variations.size,
          selected: selected.map { |v| v[:path] },
          scores: selected.map { |v| { path: File.basename(v[:path]), score: v[:score].round(3) } }
        })
      end

      # Generate prompt variations for more diversity
      def vary_prompt(base_prompt, count: 10)
        variations = [base_prompt]

        # Style modifiers
        styles = [
          'cinematic lighting', 'dramatic shadows', 'soft diffused light',
          'golden hour', 'blue hour', 'neon lit', 'candlelit', 'backlit',
          'high contrast', 'low key', 'high key', 'film noir',
          'anamorphic', 'shallow depth of field', 'tilt shift'
        ]

        # Mood modifiers
        moods = [
          'atmospheric', 'moody', 'ethereal', 'gritty', 'dreamy',
          'melancholic', 'euphoric', 'tense', 'serene', 'mysterious'
        ]

        # Technical modifiers
        technical = [
          '35mm film', '65mm IMAX', 'medium format', 'Hasselblad',
          'Kodak Portra', 'Fuji Velvia', 'Cinestill 800T', 'Tri-X pushed',
          'Zeiss lens', 'Cooke Panchro', 'anamorphic Kowa'
        ]

        (count - 1).times do
          mods = []
          mods << styles.sample if rand < 0.7
          mods << moods.sample if rand < 0.5
          mods << technical.sample if rand < 0.4

          varied = "#{base_prompt}, #{mods.join(', ')}"
          variations << varied
        end

        variations.uniq
      end

      # List active swarm sessions
      def list_sessions
        Dir.glob(File.join(OUTPUT_DIR, '*')).select { |d| File.directory?(d) }.map do |dir|
          name = File.basename(dir)
          selected = Dir.glob(File.join(dir, 'selected', '*')).size
          rejected = Dir.glob(File.join(dir, 'rejected', '*')).size
          "  #{name}: #{selected} selected, #{rejected} rejected"
        end.join("\n")
      end

      # Compare two variations side by side
      def compare(path_a, path_b)
        score_a = score_single(path_a)
        score_b = score_single(path_b)

        winner = score_a > score_b ? path_a : path_b
        {
          a: { path: path_a, score: score_a },
          b: { path: path_b, score: score_b },
          winner: winner,
          margin: (score_a - score_b).abs
        }
      end

      private

      def generate_variations(prompt, type, config, count, session_dir)
        opts = { prompt: prompt, type: type, config: config, session_dir: session_dir }
        variations = []
        prompts = config[:vary_prompt] ? vary_prompt(prompt, count: [count / 4, 5].max) : [prompt]

        count.times do |i|
          seed = config[:vary_seed] ? rand(999_999) : 42
          current_prompt = prompts.sample
          opts[:seed] = seed
          opts[:prompt] = current_prompt
          opts[:index] = i

          variation = generate_single_variation(type, opts)

          if variation && File.exist?(variation.to_s)
            variations << { path: variation, seed: seed, prompt: current_prompt, index: i }
            print '.'
          else
            print 'x'
          end
        end
        puts

        variations
      end

      def generate_single_variation(type, opts)
        case type
        when :image then generate_image_variation(opts)
        when :video then generate_video_variation(opts)
        when :audio then generate_audio_variation(opts)
        end
      end

      def generate_image_variation(opts)
        config = opts[:config]
        model = config[:vary_model] ? config[:models].sample : config[:models].first
        chain = config[:vary_chain] ? config[:chains].sample : nil
        guidance = config[:vary_guidance] ? rand(config[:guidance_range]) : 7.5

        if chain
          result = Replicate.run_chain(opts[:prompt], chain: chain, seed: opts[:seed])
          return nil unless result.ok?
          result.value[:final]
        else
          Replicate.generate_image(opts[:prompt], model: model)
        end
      rescue StandardError
        nil
      end

      def generate_video_variation(opts)
        image = Replicate.generate_image(opts[:prompt], model: :flux_schnell)
        return nil unless image && File.exist?(image.to_s)

        config = opts[:config]
        model = config[:vary_model] ? config[:models].sample : config[:models].first
        duration = config[:vary_duration] ? config[:durations].sample : 10

        Replicate.generate_video(image, opts[:prompt], model: model, duration: duration)
      rescue StandardError
        nil
      end

      def generate_audio_variation(opts)
        config = opts[:config]
        model = config[:vary_model] ? config[:models].sample : config[:models].first
        duration = config[:durations].sample

        Replicate.generate_audio(opts[:prompt], model: model, duration: duration)
      rescue StandardError
        nil
      end

      def score_variations(variations, type)
        variations.map do |v|
          score = case type
                  when :image then score_image(v[:path])
                  when :video then score_video(v[:path])
                  when :audio then score_audio(v[:path])
                  else 0.5
                  end

          v.merge(score: score)
        end
      end

      def score_image(path)
        return 0.0 unless File.exist?(path.to_s)

        # Use multiple criteria
        scores = {}

        QUALITY_CRITERIA.each do |criterion, config|
          # Quick heuristic scoring (no LLM for speed)
          scores[criterion] = heuristic_score(path, criterion)
        end

        # Weighted average
        total = 0.0
        weight_sum = 0.0

        QUALITY_CRITERIA.each do |criterion, config|
          total += scores[criterion] * config[:weight]
          weight_sum += config[:weight]
        end

        total / weight_sum
      end

      def score_single(path)
        score_image(path)
      end

      def heuristic_score(path, criterion)
        # Fast heuristic scoring based on file analysis
        # In production, this would use LLaVA or CLIP

        begin
          stat = File.stat(path)
          size_kb = stat.size / 1024.0

          case criterion
          when :aesthetic
            # Larger files often have more detail
            [size_kb / 500.0, 1.0].min * 0.6 + rand(0.4)
          when :technical
            # Medium-sized files often best quality
            distance_from_ideal = (size_kb - 300).abs / 300.0
            [1.0 - distance_from_ideal, 0.3].max * 0.7 + rand(0.3)
          when :originality
            # Random for now (would need embedding comparison)
            0.4 + rand(0.6)
          when :emotional
            # Random for now (would need sentiment analysis)
            0.3 + rand(0.7)
          else
            0.5
          end
        rescue StandardError
          0.5
        end
      end

      def score_video(path)
        return 0.0 unless File.exist?(path.to_s)

        # Basic video scoring heuristics
        stat = File.stat(path)
        size_mb = stat.size / (1024.0 * 1024.0)

        # Larger video files generally have more motion/detail
        base_score = [size_mb / 50.0, 1.0].min
        base_score * 0.7 + rand(0.3)
      end

      def score_audio(path)
        return 0.0 unless File.exist?(path.to_s)

        # Basic audio scoring
        stat = File.stat(path)
        0.5 + rand(0.5)
      end

      def organize_output(session_dir, selected, rejected)
        selected_dir = File.join(session_dir, 'selected')
        rejected_dir = File.join(session_dir, 'rejected')

        FileUtils.mkdir_p(selected_dir)
        FileUtils.mkdir_p(rejected_dir)

        selected.each_with_index do |v, i|
          next unless File.exist?(v[:path].to_s)
          ext = File.extname(v[:path])
          new_name = format('best_%02d_score_%0.3f%s', i + 1, v[:score], ext)
          FileUtils.cp(v[:path], File.join(selected_dir, new_name))
        end

        rejected.each_with_index do |v, i|
          next unless File.exist?(v[:path].to_s)
          ext = File.extname(v[:path])
          new_name = format('reject_%02d_score_%0.3f%s', i + 1, v[:score], ext)
          FileUtils.cp(v[:path], File.join(rejected_dir, new_name))
        end

        # Write metadata
        metadata = {
          timestamp: Time.now.iso8601,
          selected: selected.map { |v| { score: v[:score], seed: v[:seed], prompt: v[:prompt] } },
          rejected_count: rejected.size,
          score_range: {
            min: rejected.last&.dig(:score),
            max: selected.first&.dig(:score)
          }
        }

        File.write(File.join(session_dir, 'metadata.json'), JSON.pretty_generate(metadata))
      end
    end
  end
end
