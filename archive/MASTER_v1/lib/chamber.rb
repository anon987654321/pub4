# frozen_string_literal: true

module MASTER
  # Chamber - Multi-model deliberation for CODE REFINEMENT
  # Each model proposes diffs + writes letter defending changes
  # Arbiter cherry-picks best improvements
  #
  # NOTE: One of four deliberation/generation engines:
  #   - Chamber (this file): Code refinement via multi-model debate
  #   - CreativeChamber: Creative ideation for concepts/multimedia
  #   - Council: Opinion/judgment deliberation with fixed member roles
  #   - Swarm: Generate many variations, curate best via scoring
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
end
