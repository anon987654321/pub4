# frozen_string_literal: true

module MASTER
  class Chamber
    # Multi-model deliberation for code refinement
    # Each model proposes diffs + writes letter defending changes
    # Arbiter cherry-picks best improvements

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
        #{code[0..5000]}
        ```
      PROMPT
    end

    def review_prompt(code, other_proposals, filename)
      summaries = other_proposals.map do |p|
        "### #{p[:model]}\n#{p[:letter].to_s[0..400]}\n```diff\n#{p[:diff].to_s[0..600]}\n```"
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

      summary = @proposals.map do |p|
        rebuttals = p[:rebuttals]&.map { |r| "  - #{r[:model]}: #{r[:content].to_s[0..150]}" }&.join("\n")
        <<~ENTRY
          ### #{p[:model]}
          **Letter:** #{p[:letter].to_s[0..300]}
          **Diff:**
          ```diff
          #{p[:diff].to_s[0..500]}
          ```
          **Rebuttals:**
          #{rebuttals}
        ENTRY
      end.join("\n")

      prompt = <<~PROMPT
        You are the ARBITER. Review all proposals for #{filename}:

        #{summary}

        Your task:
        1. Evaluate each proposed change
        2. Accept changes that are clearly improvements
        3. Reject changes that are risky or unnecessary
        4. Apply accepted changes to the original code

        Return:
        ## ACCEPTED CHANGES
        List which changes you're accepting and why (one line each)

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

      # Check if rebuttals show agreement
      support_count = @proposals.sum do |p|
        p[:rebuttals]&.count { |r| r[:content].to_s.downcase.include?('agree') } || 0
      end

      support_count >= (@proposals.size * 2)
    end

    def over_budget?
      @cost >= MAX_COST_PER_FILE
    end
  end
end
