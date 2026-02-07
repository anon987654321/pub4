# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 1: Pass text through, load persona
    class Intake
      def call(input)
        text = input[:text] || ""
        if input[:persona]
          persona = DB.get_persona(input[:persona].to_s)
          input = input.merge(persona_instructions: persona&.dig("instructions"))
        end
        Result.ok(input.merge(text: text))
      end
    end

    # Stage 2: Block dangerous patterns
    class Guard
      DENY = [
        /rm\s+-r[f]?\s+\//, />\s*\/dev\/[sh]da/, /DROP\s+TABLE/i,
        /FORMAT\s+[A-Z]:/i, /mkfs\./, /dd\s+if=/
      ].freeze

      def call(input)
        text = input[:text] || ""
        match = DENY.find { |p| p.match?(text) }
        match ? Result.err("Blocked: dangerous pattern") : Result.ok(input)
      end
    end

    # Stage 3: Route to model via circuit breaker + budget
    class Route
      def call(input)
        text = input[:text] || ""
        selected = LLM.select_model(text.length)
        return Result.err("All models unavailable") unless selected
        Result.ok(input.merge(
          model: selected[:model],
          tier: selected[:tier],
          budget_remaining: LLM.remaining
        ))
      end
    end

    # Stage 4: Adversarial council debate (optional)
    class Debate
      MAX_ROUNDS = 3

      def call(input)
        return Result.ok(input) unless input[:debate]

        personas = DB.council_personas || []
        return Result.ok(input) if personas.empty?

        text = input[:text] || ""
        model = input[:model]
        chat = LLM.chat(model: model)

        rounds = []
        current = text

        MAX_ROUNDS.times do |i|
          persona = personas[i % personas.size]
          prompt = "#{persona['instructions']}\n\nReview:\n#{current}"

          begin
            response = chat.ask(prompt)
            rounds << { persona: persona["name"], response: response.content }
            current = response.content
          rescue => e
            break
          end
        end

        Result.ok(input.merge(debate_rounds: rounds, debated: current))
      end
    end

    # Stage 5: Query LLM, stream to stderr
    class Ask
      def call(input)
        model = input[:model]
        return Result.err("No model selected") unless model

        chat = LLM.chat(model: model)
        persona = input[:persona_instructions]
        chat.with_instructions(persona) if persona && chat.respond_to?(:with_instructions)

        text = input[:debated] || input[:text] || ""

        begin
          response = chat.ask(text) do |chunk|
            $stderr.print chunk.content if chunk.content
          end
          $stderr.puts

          tokens_in  = response.input_tokens  rescue 0
          tokens_out = response.output_tokens rescue 0
          LLM.record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)
          LLM.reset!(model)

          Result.ok(input.merge(
            response: response.content,
            tokens_in: tokens_in,
            tokens_out: tokens_out
          ))
        rescue => e
          LLM.trip!(model)
          Result.err("LLM error (#{model}): #{e.message}")
        end
      end
    end

    # Stage 6: Axiom enforcement
    class Lint
      def call(input)
        text = input[:response] || ""
        axioms = DB.axioms rescue []
        violations = []

        axioms.each do |axiom|
          pattern = axiom["pattern"]
          next unless pattern
          violations << axiom["name"] if text.match?(Regexp.new(pattern, Regexp::IGNORECASE))
        end

        if violations.any?
          Result.ok(input.merge(axiom_violations: violations, linted: true))
        else
          Result.ok(input.merge(axiom_violations: [], linted: true))
        end
      end
    end

    # Stage 7: Format output (typography)
    class Render
      CODE_FENCE = /^```/

      def call(input)
        text = input[:response] || ""
        Result.ok(input.merge(rendered: typeset(text)))
      end

      private

      def typeset(text)
        regions = []
        current = []
        in_code = false

        text.each_line do |line|
          if line.match?(CODE_FENCE)
            regions << { text: current.join, code: in_code } unless current.empty?
            current = [line]
            in_code = !in_code
            unless in_code
              regions << { text: current.join, code: true }
              current = []
            end
          else
            current << line
          end
        end
        regions << { text: current.join, code: in_code } unless current.empty?

        regions.map { |r| r[:code] ? r[:text] : prose(r[:text]) }.join
      end

      def prose(text)
        text.gsub(/"([^"]*?)"/) { "\u201C#{$1}\u201D" }
            .gsub(/\s--\s/, " \u2014 ")
            .gsub(/\.\.\./, "\u2026")
      end
    end

    # Sandboxed code execution (pledge on OpenBSD)
    class Execute
      def call(input)
        response = input[:response] || ""
        blocks = response.scan(/```(?:ruby|rb)\n(.*?)```/m).flatten
        return Result.ok(input.merge(executed: false)) if blocks.empty?

        require "tempfile"
        results = blocks.map { |code| run(code) }
        all_ok = results.all? { |r| r[:success] }
        Result.ok(input.merge(executed: true, success: all_ok, exec_results: results))
      end

      private

      def run(code)
        Tempfile.create(["master", ".rb"]) do |f|
          f.write(code)
          f.flush
          begin
            Pledge.unveil(f.path, "r")
            Pledge.pledge("stdio rpath")
          rescue => e
            # Not on OpenBSD
          end
          output = IO.popen(["ruby", f.path], err: [:child, :out], &:read)
          { success: $?.success?, output: output, exit_code: $?.exitstatus }
        end
      end
    end
  end
end
