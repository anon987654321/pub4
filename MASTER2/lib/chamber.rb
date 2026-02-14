# frozen_string_literal: true

module MASTER
  # Chamber - Multi-model deliberation with council personas
  # Implements multi-round debate: Independent → Synthesis → Convergence
  class Chamber
    MAX_ROUNDS = 25
    MAX_COST = 0.50
    CONSENSUS_THRESHOLD = 0.70
    CONVERGENCE_THRESHOLD = 0.05

    MODELS = {
      sonnet: nil,    # Will be resolved via LLM.pick
      deepseek: nil,  # Will be resolved via LLM.pick
      gemini: nil,    # Will be resolved via LLM.pick
    }.freeze

    ARBITER = :sonnet

    attr_reader :cost, :rounds, :proposals

    def initialize(llm: LLM)
      @llm = llm
      @cost = 0.0
      @rounds = 0
      @proposals = []
    end

    def arbiter_model
      LLM.model_tiers[:strong]&.first || "anthropic/claude-sonnet-4"
    end

    # Convenience method for single council review
    # @param text [String] Code or text to review
    # @param model [String, nil] Optional model override
    # @return [Hash] Review result with votes and consensus
    class << self
      def council_review(text, model: nil)
        chamber = new(llm: LLM)
        chamber.council_review(text, text, model: model)
      end
    end

    def deliberate(code, filename: "code", participants: %i[sonnet deepseek])
      @proposals = []
      @rounds = 0

      participants.each do |model_key|
        break if over_budget?

        model = MODELS[model_key] || LLM.pick
        next unless model && @llm.circuit_closed?(model)

        proposal = propose(code, model, filename)
        @proposals << { model: model_key, proposal: proposal } if proposal
      end

      return Result.err("No proposals generated") if @proposals.empty?

      council_result = multi_round_review(code, @proposals.first[:proposal])

      arbiter_model = MODELS[ARBITER] || LLM.pick(:strong)
      if @llm.circuit_closed?(arbiter_model)
        final = arbiter_decision(code, @proposals, arbiter_model)
        Result.ok(
          original: code,
          proposals: @proposals,
          council: council_result,
          final: final,
          cost: @cost,
          rounds: @rounds,
        )
      else
        Result.ok(
          original: code,
          proposals: @proposals,
          council: council_result,
          final: @proposals.first[:proposal],
          cost: @cost,
          rounds: @rounds,
        )
      end
    end

    def multi_round_review(original, proposal)
      personas = DB.council
      return { passed: true, votes: [], vetoed_by: [], rounds: 0 } if personas.empty?

      all_rounds = []
      previous_consensus = 0.0
      final_result = nil

      MAX_ROUNDS.times do |round_num|
        break if over_budget?

        round_result = council_review(original, proposal, model: nil)
        all_rounds << round_result

        if round_result[:vetoed_by]&.any?
          return round_result.merge(rounds: round_num + 1, all_rounds: all_rounds)
        end

        current_consensus = round_result[:consensus] || 0
        delta = (current_consensus - previous_consensus).abs

        if round_num > 0 && delta < CONVERGENCE_THRESHOLD
          return round_result.merge(
            rounds: round_num + 1,
            converged: true,
            all_rounds: all_rounds,
          )
        end

        if current_consensus >= CONSENSUS_THRESHOLD
          return round_result.merge(rounds: round_num + 1, all_rounds: all_rounds)
        end

        if round_num < MAX_ROUNDS - 1 && !over_budget?
          proposal = synthesize(proposal, round_result[:votes])
        end

        previous_consensus = current_consensus
        final_result = round_result
      end

      (final_result || {}).merge(
        rounds: MAX_ROUNDS,
        converged: false,
        halted: true,
        all_rounds: all_rounds,
      )
    end

    def council_review(original, proposal, model: nil)
      personas = DB.council
      return { passed: true, votes: [], vetoed_by: [] } if personas.empty?

      votes = []
      vetoed_by = []
      veto_personas = personas.select { |p| p[:veto] }
      advisory_personas = personas.reject { |p| p[:veto] }

      veto_personas.first(3).each do |persona|
        break if over_budget?
        vote = get_persona_vote(persona, original, proposal)
        votes << vote
        if vote[:veto]
          vetoed_by << persona[:name]
          return { passed: false, verdict: :rejected, vetoed_by: vetoed_by, votes: votes }
        end
      end

      advisory_personas.first(3).each do |persona|
        break if over_budget?
        votes << get_persona_vote(persona, original, proposal)
      end

      total_weight = votes.sum { |v| v[:weight] || 0.1 }
      approve_weight = votes.select { |v| v[:approve] }.sum { |v| v[:weight] || 0.1 }
      consensus = total_weight > 0 ? (approve_weight / total_weight) : 0

      {
        passed: consensus >= CONSENSUS_THRESHOLD,
        verdict: consensus >= CONSENSUS_THRESHOLD ? :approved : :rejected,
        consensus: consensus.round(2),
        vetoed_by: [],
        votes: votes,
      }
    end

    # Creative mode: Brainstorm → Critique → Synthesize cycle
    # Merged from CreativeChamber
    def ideate(prompt:, constraints: [], cycles: 2)
      ideas = []
      critiques = []
      total_cost = 0

      cycles.times do
        brainstorm = generate_ideas(prompt, ideas, constraints)
        return brainstorm if brainstorm.err?
        ideas += brainstorm.value[:ideas]
        total_cost += brainstorm.value[:cost]

        critique = critique_ideas(ideas)
        return critique if critique.err?
        critiques << critique.value[:critique]
        total_cost += critique.value[:cost]
      end

      synthesis = synthesize_ideas(prompt, ideas, critiques, constraints)
      return synthesis if synthesis.err?
      total_cost += synthesis.value[:cost]

      Result.ok(
        ideas: ideas,
        critiques: critiques,
        final: synthesis.value[:synthesis],
        cost: total_cost
      )
    end

    private

    def synthesize(proposal, votes)
      rejections = votes.select { |v| !v[:approve] }
      return proposal if rejections.empty? || over_budget?

      concerns = rejections.map { |v| "#{v[:name]}: #{v[:reason]}" }.join("\n")

      prompt = <<~PROMPT
        The council raised these concerns about the proposal:

        #{concerns}

        CURRENT PROPOSAL (first 1500 chars):
        #{proposal[0, 1500]}

        Revise the proposal to address these concerns.
        Output ONLY the revised proposal, no explanation.
      PROMPT

      result = @llm.ask(prompt, tier: :fast)
      return proposal unless result.ok?

      data = result.value
      @cost += data[:cost] || 0
      @rounds += 1

      data[:content]
    rescue StandardError => e
      DB.append("errors", { context: "chamber_synthesize", error: e.message, time: Time.now.utc.iso8601 })
      proposal
    end

    def get_persona_vote(persona, original, proposal)
      return { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 } if over_budget?

      prompt = <<~PROMPT
        You are #{persona[:name]}.
        #{persona[:directive] || persona[:style]}

        Review this proposed change:

        ORIGINAL (first 500 chars):
        #{original[0, 500]}

        PROPOSED (first 500 chars):
        #{proposal[0, 500]}

        Respond with ONLY one word: APPROVE or REJECT
        Then one sentence explaining why.
      PROMPT

      result = @llm.ask(prompt, tier: :fast)
      return { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 } unless result.ok?

      data = result.value
      @cost += data[:cost] || 0

      content = data[:content].to_s.strip
      approve = content.upcase.start_with?("APPROVE")
      veto = persona[:veto] && content.upcase.start_with?("REJECT")

      {
        name: persona[:name],
        approve: approve,
        veto: veto,
        weight: persona[:weight] || 0.1,
        reason: content.split("\n").last,
      }
    rescue StandardError => e
      DB.append("errors", { context: "chamber_vote", persona: persona[:name], error: e.message, time: Time.now.utc.iso8601 })
      { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 }
    end

    def propose(code, model, filename)
      @rounds += 1

      prompt = <<~PROMPT
        Review this code and propose improvements:
        FILE: #{filename}

        ```
        #{code[0, 4000]}
        ```

        Provide:
        1. ISSUES: What's wrong (bullet points)
        2. DIFF: Proposed changes (unified diff format)
        3. RATIONALE: Why these changes (one paragraph)
      PROMPT

      result = @llm.ask(prompt, model: model)
      return nil unless result.ok?

      data = result.value
      @cost += data[:cost] || 0

      data[:content]
    rescue StandardError
      @llm.open_circuit!(model)
      nil
    end

    def arbiter_decision(original, proposals, model)
      prompt = <<~PROMPT
        You are the arbiter. Given these proposals, pick the best changes:

        ORIGINAL:
        ```
        #{original[0, 2000]}
        ```

        PROPOSALS:
        #{proposals.map { |p| "#{p[:model]}:\n#{p[:proposal][0, 1000]}" }.join("\n\n")}

        Output ONLY the final improved code. No explanation.
      PROMPT

      result = @llm.ask(prompt, model: model)
      return proposals.first[:proposal] unless result.ok?

      data = result.value
      @cost += data[:cost] || 0

      data[:content]
    rescue StandardError
      proposals.first[:proposal]
    end

    def over_budget?
      @cost >= MAX_COST
    end

    private

    def generate_ideas(prompt, existing_ideas, constraints)
      system_prompt = <<~SYS
        You are a creative visionary. Generate 3-5 novel ideas.
        Be bold, unconventional, surprising.
        Constraints to respect: #{constraints.join(', ')}
        #{"Previous ideas (don't repeat): #{existing_ideas.join(', ')}" if existing_ideas.any?}
      SYS

      full_prompt = "#{system_prompt}\n\nGenerate ideas for: #{prompt}"
      result = @llm.ask(full_prompt, tier: :strong)

      if result.ok?
        data = result.value
        content = data[:content].to_s
        parsed = content.scan(/^[\-\*•]\s*(.+)/).flatten
        parsed = [content] if parsed.empty?
        Result.ok(ideas: parsed, cost: data[:cost] || 0)
      else
        Result.err("Brainstorm failed: #{result.error}")
      end
    end

    def critique_ideas(ideas)
      critique_prompt = <<~PROMPT
        Critique these ideas honestly. What are the weaknesses, blind spots, implementation challenges?

        Ideas:
        #{ideas.map { |i| "- #{i}" }.join("\n")}
      PROMPT

      result = @llm.ask(critique_prompt, tier: :fast)

      if result.ok?
        data = result.value
        Result.ok(critique: data[:content], cost: data[:cost] || 0)
      else
        Result.err("Critique failed: #{result.error}")
      end
    end

    def synthesize_ideas(original_prompt, ideas, critiques, constraints)
      prompt = <<~PROMPT
        Original goal: #{original_prompt}
        Constraints: #{constraints.join(', ')}

        Ideas generated:
        #{ideas.map { |i| "- #{i}" }.join("\n")}

        Critiques:
        #{critiques.join("\n---\n")}

        Synthesize the best elements into a cohesive recommendation.
        Address the valid critiques.
        Be practical but preserve innovation.
      PROMPT

      result = @llm.ask(prompt, tier: :strong)

      if result.ok?
        data = result.value
        Result.ok(synthesis: data[:content], cost: data[:cost] || 0)
      else
        Result.err("Synthesis failed: #{result.error}")
      end
    end
  end

  # CreativeChamber - Multi-model deliberation for CREATIVE IDEATION
  # Generates ideas/conversations, scores them, then generates multimedia via Replicate
  #
  # NOTE: One of four deliberation/generation engines:
  #   - Chamber: Code refinement via multi-model debate
  #   - CreativeChamber (this class): Creative ideation for concepts/multimedia
  #   - Council: Opinion/judgment deliberation with fixed member roles
  #   - Swarm: Generate many variations, curate best via scoring
  #
  # Ported from MASTER v1, adapted for MASTER2's Result monad and LLM.ask API
  class CreativeChamber
    # String slice limits for output truncation
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

    ARBITER_TIER = :strong
    MAX_COST = 2.00

    attr_reader :cost, :results

    def initialize
      @cost = 0.0
      @results = []
    end

    # Idea brainstorming - multiple models propose and debate
    def brainstorm(topic, rounds: 2, participants: 3)
      @results = []

      # Round 1: Each model proposes ideas
      proposals = []
      participants.times do |i|
        break if over_budget?

        result = ask_llm("You are a creative thinker brainstorming ideas about: #{topic}\n\nGenerate 3-5 distinct, innovative ideas. Be specific and actionable.", tier: :fast)
        next unless result.ok?

        proposal = {
          model: i,
          ideas: result.value[:content],
          critique: nil
        }
        @results << { type: :proposal, **proposal }
        proposals << proposal
      end

      return Result.ok({ ideas: [], cost: @cost }) if proposals.empty?

      # Round 2: Each model critiques others and defends their own
      proposals.each_with_index do |prop, i|
        break if over_budget?

        others = proposals.reject.with_index { |_, j| j == i }.map { |p| p[:ideas][0...MAX_IDEA_PREVIEW] }.join("\n\n")
        critique_prompt = "You proposed these ideas:\n#{prop[:ideas][0...MAX_PROPOSAL_PREVIEW]}\n\nOthers proposed:\n#{others}\n\nCritique the other ideas and explain why yours are better. Be constructive but persuasive."
        
        result = ask_llm(critique_prompt, tier: :fast)
        if result.ok?
          prop[:critique] = result.value[:content]
          @results << { type: :critique, model: i, content: prop[:critique] }
        end
      end

      # Arbiter synthesizes best ideas
      synthesis = arbiter_synthesize(topic, proposals)
      Result.ok({ ideas: proposals, synthesis: synthesis, cost: @cost })
    end

    # Image variations - multiple models interpret same prompt
    def image_variations(prompt, count: 2)
      return Result.ok({ images: [], cost: @cost }) unless Replicate.available?

      images = []
      count.times do
        break if over_budget?

        result = Replicate.generate(prompt: prompt, model: :flux)
        if result.ok?
          images << result.value
          @results << { type: :image, **result.value }
        end
      end

      Result.ok({ images: images, cost: @cost })
    end

    # Video storyboard - LLMs propose scenes, arbiter picks, generate via Replicate
    def video_storyboard(concept, scenes: 3)
      return Result.ok({ storyboard: [], cost: @cost }) unless Replicate.available?

      # Step 1: Generate scene descriptions
      result = ask_llm("Create a #{scenes}-scene video storyboard for: #{concept}\n\nFor each scene, describe the visual composition, camera angle, mood, and key elements. Be vivid and specific.", tier: :strong)
      return Result.err("Failed to generate storyboard") unless result.ok?

      scene_text = result.value[:content]
      @results << { type: :storyboard_text, content: scene_text }

      # Step 2: Extract individual scenes and generate images
      storyboard = []
      scene_text.split(/Scene \d+/).drop(1).take(scenes).each_with_index do |scene_desc, i|
        break if over_budget?

        prompt = "Cinematic scene: #{scene_desc[0...MAX_DETAIL_PREVIEW]}"
        img_result = Replicate.generate(prompt: prompt, model: :flux)
        if img_result.ok?
          storyboard << { scene: i + 1, description: scene_desc.strip, **img_result.value }
          @results << { type: :scene, scene: i + 1, **img_result.value }
        end
      end

      Result.ok({ storyboard: storyboard, cost: @cost })
    end

    # Simulate conversation - role-play dialogue across turns
    def simulate_conversation(scenario, turns: 4, participants: 2)
      @results = []
      dialogue = []

      turns.times do |turn|
        participants.times do |speaker|
          break if over_budget?

          context = dialogue.map { |d| "#{d[:speaker]}: #{d[:text]}" }.join("\n")
          prompt = "Scenario: #{scenario}\n\nConversation so far:\n#{context}\n\nYou are Speaker #{speaker + 1}. Respond naturally to continue the conversation."
          
          result = ask_llm(prompt, tier: :fast)
          if result.ok?
            line = { speaker: speaker + 1, turn: turn + 1, text: result.value[:content] }
            dialogue << line
            @results << { type: :dialogue, **line }
          end
        end
      end

      Result.ok({ dialogue: dialogue, cost: @cost })
    end

    # Enhance prompt - iterative refinement through multi-model debate
    def enhance_prompt(initial_prompt, iterations: 2)
      current = initial_prompt
      history = [{ version: 0, prompt: current }]

      iterations.times do |i|
        break if over_budget?

        # Get enhancement suggestions
        result = ask_llm("This is an AI prompt:\n\n#{current}\n\nSuggest 3 specific improvements to make it more effective, clear, and detailed. Focus on actionable changes.", tier: :fast)
        next unless result.ok?

        suggestions = result.value[:content]

        # Apply improvements
        enhance_result = ask_llm("Original prompt:\n#{current}\n\nSuggestions:\n#{suggestions}\n\nRewrite the prompt incorporating these improvements. Return only the improved prompt.", tier: :strong)
        if enhance_result.ok?
          current = enhance_result.value[:content]
          history << { version: i + 1, prompt: current, suggestions: suggestions }
          @results << { type: :enhancement, version: i + 1, suggestions: suggestions }
        end
      end

      Result.ok({ final_prompt: current, history: history, cost: @cost })
    end

    # Analyze competitors - research competitive landscape & identify gaps
    def analyze_competitors(product, competitors: [])
      @results = []

      # Analyze each competitor
      analyses = competitors.map do |competitor|
        break if over_budget?

        prompt = "Analyze this competitor: #{competitor}\n\nIn the context of building: #{product}\n\nIdentify their strengths, weaknesses, and unique features. Be specific and critical."
        result = ask_llm(prompt, tier: :strong)
        
        if result.ok?
          analysis = { competitor: competitor, analysis: result.value[:content] }
          @results << { type: :competitor_analysis, **analysis }
          analysis
        end
      end.compact

      # Synthesize gaps and opportunities
      if analyses.any? && !over_budget?
        all_analyses = analyses.map { |a| "#{a[:competitor]}:\n#{a[:analysis][0...MAX_DETAIL_PREVIEW]}" }.join("\n\n")
        synthesis_prompt = "Based on these competitor analyses:\n\n#{all_analyses}\n\nFor building: #{product}\n\nIdentify 5 key opportunities or gaps in the market. What features or approaches are missing?"
        
        synthesis_result = ask_llm(synthesis_prompt, tier: :strong)
        if synthesis_result.ok?
          @results << { type: :synthesis, content: synthesis_result.value[:content] }
          return Result.ok({ analyses: analyses, opportunities: synthesis_result.value[:content], cost: @cost })
        end
      end

      Result.ok({ analyses: analyses, opportunities: nil, cost: @cost })
    end

    # Feature ideation - generate new feature ideas
    def ideate_features(product_description, constraints: nil, count: 5)
      constraints_text = constraints ? "\n\nConstraints:\n#{constraints}" : ""
      prompt = "Product: #{product_description}#{constraints_text}\n\nGenerate #{count} innovative feature ideas. For each:\n1. Name\n2. One-line description\n3. User value\n4. Technical complexity (Low/Med/High)\n\nBe creative but realistic."

      result = ask_llm(prompt, tier: :strong)
      return Result.err("Failed to generate features") unless result.ok?

      content = result.value[:content]
      @results << { type: :features, content: content }

      Result.ok({ features: content, cost: @cost })
    end

    private

    def ask_llm(prompt, tier: :fast)
      LLM.ask(prompt, tier: tier).tap do |result|
        if result.ok?
          @cost += result.value[:cost] || 0.0
        end
      end
    end

    def arbiter_synthesize(topic, proposals)
      return nil if over_budget?

      ideas_summary = proposals.map.with_index do |p, i|
        "Model #{i + 1} Ideas:\n#{p[:ideas][0...MAX_IDEA_PREVIEW]}\n\nCritique:\n#{p[:critique]&.[](0...MAX_LETTER_PREVIEW) || 'None'}"
      end.join("\n\n---\n\n")

      prompt = "Topic: #{topic}\n\nMultiple models brainstormed ideas and critiqued each other:\n\n#{ideas_summary}\n\nAs an impartial arbiter, synthesize the BEST 3 ideas from all proposals. Explain why each is strong. Be objective and decisive."

      result = ask_llm(prompt, tier: ARBITER_TIER)
      if result.ok?
        synthesis = result.value[:content]
        @results << { type: :synthesis, content: synthesis }
        synthesis
      else
        nil
      end
    end

    def over_budget?
      @cost >= MAX_COST
    end
  end

  # Swarm - Generate many variations, curate best
  class Swarm
    SWARM_SIZE = 5

    def initialize(size: SWARM_SIZE)
      @size = size
    end

    def generate(prompt:, context: {})
      responses = []
      total_cost = 0

      # Fan out - get multiple responses using different approaches
      @size.times do |i|
        tier = i < 2 ? :strong : :fast  # Mix of tiers for diversity
        
        begin
          result = LLM.ask(prompt, tier: tier)
          next unless result.ok?

          data = result.value
          cost = data[:cost] || 0
          total_cost += cost

          responses << {
            index: i,
            model: data[:model],
            content: data[:content],
            tokens: (data[:tokens_in] || 0) + (data[:tokens_out] || 0)
          }
        rescue StandardError => e
          # Continue with other attempts
        end
      end

      return Result.err("No responses generated") if responses.empty?

      # Curate - pick the best response
      best = curate(responses, prompt: prompt)
      total_cost += best[:curation_cost] || 0

      Result.ok({
        responses: responses,
        best: best[:selected],
        reasoning: best[:reasoning],
        cost: total_cost
      })
    end

    private

    def curate(responses, prompt:)
      return { selected: responses.first, reasoning: "Only one response", curation_cost: 0 } if responses.size == 1

      curation_prompt = build_curation_prompt(responses, prompt)
      
      result = LLM.ask(curation_prompt, tier: :fast)
      return { selected: responses.first, reasoning: "Curation failed", curation_cost: 0 } unless result.ok?

      data = result.value
      cost = data[:cost] || 0

      # Parse selection
      content = data[:content].to_s
      selected_idx = content.match(/\[(\d+)\]/)[1].to_i rescue 0

      {
        selected: responses[selected_idx] || responses.first,
        reasoning: content,
        curation_cost: cost
      }
    rescue StandardError => e
      { selected: responses.first, reasoning: "Curation failed: #{e.message}", curation_cost: 0 }
    end

    def build_curation_prompt(responses, original_prompt)
      options = responses.map.with_index do |r, i|
        "=== Response [#{i}] (#{r[:model]}) ===\n#{r[:content][0, 500]}"
      end.join("\n\n")

      <<~PROMPT
        Original request: #{original_prompt[0, 200]}

        #{options}

        Select the best response. Reply with [N] where N is the index, followed by a brief explanation.
      PROMPT
    end
  end
end
