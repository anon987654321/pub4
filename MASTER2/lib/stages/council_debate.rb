# frozen_string_literal: true

module MASTER
  module Stages
    # Adversarial Council: Multi-persona debate with veto logic
    class CouncilDebate
      def call(input)
        text = input[:text] || input[:original_text] || ""
        
        # Load council members from DB
        members = DB.get_council_members
        return Result.err("No council members found") if members.empty?

        # Load council parameters
        threshold = (DB.get_config("council_consensus_threshold") || "0.70").to_f
        veto_precedence = (DB.get_config("council_veto_precedence") || "security,attacker,maintainer").split(",")

        # Load axioms for context
        axioms = input[:axioms] || DB.get_axioms(protection: "PROTECTED") || []
        axioms_text = axioms.map { |a| "- #{a['title']}: #{a['statement']}" }.join("\n")

        # Collect responses from each persona
        responses = []
        vetoes = []

        # Try to select an LLM model
        model = LLM.select_model(text.length)
        use_llm = !model.nil?

        if use_llm
          members.each do |member|
            begin
              # Construct prompt for this council member
              prompt = build_prompt(member, text, axioms_text)

              # Make LLM call
              chat = LLM.chat(model: model)
              llm_response = chat.ask(prompt)

              # Parse response
              decision, reasoning = parse_llm_response(llm_response.content)

              # Track cost
              if llm_response.respond_to?(:tokens_in) && llm_response.respond_to?(:tokens_out)
                LLM.record_cost(
                  model: model,
                  tokens_in: llm_response.tokens_in || 0,
                  tokens_out: llm_response.tokens_out || 0
                )
              end

              # Track success
              LLM.record_success(model)

              response = {
                slug: member["slug"],
                name: member["name"],
                weight: member["weight"],
                veto: member["veto"] == 1,
                decision: decision,
                reasoning: reasoning
              }

              responses << response
              vetoes << response if response[:veto] && response[:decision] == :veto
            rescue => e
              # LLM call failed, track failure and fall back to stub
              LLM.record_failure(model) if model
              
              # Fall back to stub behavior
              response = {
                slug: member["slug"],
                name: member["name"],
                weight: member["weight"],
                veto: member["veto"] == 1,
                decision: :approve,
                reasoning: "LLM unavailable (#{e.message}), defaulting to approval"
              }

              responses << response
            end
          end
        else
          # No model available, use stub behavior
          warn "No LLM model available (budget exhausted or all circuits tripped). Using stub responses."
          
          members.each do |member|
            response = {
              slug: member["slug"],
              name: member["name"],
              weight: member["weight"],
              veto: member["veto"] == 1,
              decision: :approve,
              reasoning: "LLM unavailable, defaulting to approval"
            }

            responses << response
          end
        end

        # Check for vetoes (precedence order matters)
        unless vetoes.empty?
          veto = vetoes.first
          return Result.err("VETOED by #{veto[:name]}: #{veto[:reasoning]}")
        end

        # Calculate weighted consensus
        approvals = responses.select { |r| r[:decision] == :approve }
        total_weight = responses.sum { |r| r[:weight] }
        approval_weight = approvals.sum { |r| r[:weight] }
        consensus_score = total_weight.positive? ? approval_weight / total_weight : 0.0

        if consensus_score < threshold
          return Result.err("Consensus not reached: #{(consensus_score * 100).round}% < #{(threshold * 100).round}%")
        end

        # Merge council recommendations into output
        enriched = input.merge(
          council_responses: responses,
          consensus_score: consensus_score,
          consensus_reached: true
        )

        Result.ok(enriched)
      end

      private

      def build_prompt(member, text, axioms_text)
        <<~PROMPT
          You are: #{member['name']}
          Your role: #{member['directive']}

          Relevant axioms to consider:
          #{axioms_text}

          Input to review:
          #{text}

          Provide your decision as one of: APPROVE, REJECT, or VETO (if you have veto power).
          Then explain your reasoning.

          Format your response as:
          DECISION: [APPROVE|REJECT|VETO]
          REASONING: [your explanation]
        PROMPT
      end

      def parse_llm_response(content)
        # Extract decision
        decision_match = content.match(/DECISION:\s*(APPROVE|REJECT|VETO)/i)
        decision = if decision_match
          case decision_match[1].upcase
          when "APPROVE" then :approve
          when "REJECT" then :reject
          when "VETO" then :veto
          else :approve
          end
        else
          :approve  # Default to approve if we can't parse
        end

        # Extract reasoning
        reasoning_match = content.match(/REASONING:\s*(.+)/m)
        reasoning = if reasoning_match
          reasoning_match[1].strip
        else
          content.strip  # Use entire content if we can't parse
        end

        [decision, reasoning]
      end
    end
  end
end
