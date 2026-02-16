# frozen_string_literal: true

module MASTER
  # CreativeChamber - Multi-model deliberation for CREATIVE IDEATION
  # Generates ideas/conversations, scores them, then generates multimedia via Replicate
  # NOTE: One of four deliberation/generation engines:
  #   - Council: Code refinement via multi-model debate
  #   - CreativeChamber (this class): Creative ideation for concepts/multimedia
  #   - Stages::Council: Opinion/judgment deliberation with fixed member roles
  #   - Swarm: Generate many variations, curate best via scoring
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
      return Result.err("Failed to generate storyboard.") unless result.ok?

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
      return Result.err("Failed to generate features.") unless result.ok?

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
end
