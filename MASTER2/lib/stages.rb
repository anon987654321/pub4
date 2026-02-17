# frozen_string_literal: true

require "yaml"
require "timeout"
require "rbconfig"

module MASTER
  module Stages
    # Stage 1: Pass text through, load persona
    class Intake
      def call(input)
        text = input[:text] || ""
        Result.ok(input.merge(text: text))
      end
    end

    # Stage 2: Strip filler words and verbose phrases
    class Compress
      COMPRESSION_FILE = File.join(__dir__, "..", "data", "compression.yml")

      class << self
        # @return [Hash] Hash with :fillers and :phrases arrays
        def patterns
          @patterns ||= load_patterns
        end

        # @return [Hash] Compiled regex patterns
        def load_patterns
          return { fillers: [], phrases: [] } unless File.exist?(COMPRESSION_FILE)

          data = YAML.safe_load_file(COMPRESSION_FILE)
          {
            fillers: (data["fillers"] || []).map { |w| /\b#{Regexp.escape(w)}\b/i },
            phrases: (data["phrases"] || []).map { |p| /#{Regexp.escape(p)}/i },
          }
        end
      end

      def call(input)
        text = input[:text] || ""
        original_length = text.length

        # Strip filler words
        self.class.patterns[:fillers].each do |pattern|
          text = text.gsub(pattern, "")
        end

        # Simplify verbose phrases
        self.class.patterns[:phrases].each do |pattern|
          text = text.gsub(pattern, "")
        end

        # Clean up extra spaces
        text = text.gsub(/\s{2,}/, " ").strip
        compressed = original_length - text.length

        Result.ok(input.merge(text: text, bytes_compressed: compressed))
      end
    end

    # Stage 3: Block dangerous patterns
    class Guard
      DANGEROUS_PATTERNS = [
        /rm\s+-r[f]?\s+\//,
        />\s*\/dev\/[sh]da/,
        /DROP\s+TABLE/i,
        /FORMAT\s+[A-Z]:/i,
        /mkfs\./,
        /dd\s+if=/,
      ].freeze

      def call(input)
        text = input[:text] || ""
        match = DANGEROUS_PATTERNS.find { |p| p.match?(text) }
        match ? Result.err("Blocked: dangerous pattern detected.") : Result.ok(input)
      end
    end

    # Stage 4: Route to model via circuit breaker + budget
    class Route
      def call(input)
        tier = LLM.tier
        model = LLM.select_model
        return Result.err("All models unavailable.") unless model
        Result.ok(input.merge(model: model, tier: tier, budget_remaining: LLM.budget_remaining))
      end
    end

    # Stage 5: Adversarial council review (delegates to Council)
    class Council
      def call(input)
        text = input[:text] || ""
        model = input[:model]
        return Result.ok(input) unless model

        # NOTE: model: param is accepted by Council.council_review but currently unused
        review = MASTER::Council.council_review(text, model: model)
        Result.ok(input.merge(
          council_verdict: review[:verdict],
          council_vetoed: review[:vetoed_by].any?,
          council_vetoes: review[:vetoed_by],
          council_votes: review[:votes],
        ))
      end
    end

    # Stage 6: Query LLM, stream to stderr
    class Ask
      def call(input)
        model = input[:model]
        return Result.err("No model selected.") unless model

        model_short = model.split("/").last
        tier = input[:tier] || :unknown
        puts UI.dim("llm0: #{tier} #{model_short}")

        text = input[:text] || ""

        result = LLM.ask(text, model: model, stream: true)

        if result.ok?
          data = result.value
          tokens_in = data[:tokens_in] || 0
          tokens_out = data[:tokens_out] || 0
          cost = data[:cost] || 0

          puts UI.dim("llm0: #{tokens_in}->#{tokens_out} tok, #{UI.currency_precise(cost)}")

          Result.ok(input.merge(
            response: data[:content],
            tokens_in: tokens_in,
            tokens_out: tokens_out,
            cost: cost,
          ))
        else
          Result.err("LLM error (#{model}): #{result.error}.")
        end
      end
    end

    # Stage 7: Axiom enforcement
    class Lint
      REGEX_TIMEOUT = 0.1 # seconds

      def call(input)
        text = input[:response] || ""
        axioms = DB.axioms
        violations = []

        axioms.each do |axiom|
          pattern = axiom[:pattern]
          next unless pattern

          begin
            re = Regexp.new(pattern, Regexp::IGNORECASE)
            matched = Timeout.timeout(REGEX_TIMEOUT) { text.match?(re) }
            violations << axiom[:name] if matched
          rescue RegexpError, Timeout::Error
            # Skip invalid or pathological patterns
            next
          end
        end

        # Run NNG usability heuristics check if enabled
        design_violations = []
        if ENV['MASTER_CHECK_DESIGN'] == 'true' && defined?(NNGChecklist)
          result = NNGChecklist.validate(text)
          design_violations = result.value if result.ok?
        end

        Result.ok(input.merge(
          axiom_violations: violations,
          design_violations: design_violations,
          linted: true
        ))
      end
    end

    # Stage 8: Format output (typography)
    class Render
      CODE_FENCE = /^```/.freeze

      def call(input)
        text = input[:response] || ""
        Result.ok(input.merge(rendered: apply_typography(text)))
      end

      private

      def apply_typography(text)
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

        regions.map { |r| r[:code] ? r[:text] : beautify_prose(r[:text]) }.join
      end

      def beautify_prose(text)
        text
          .gsub(/"([^"]*?)"/) { "\u201C#{Regexp.last_match(1)}\u201D" }
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
        Tempfile.create(%w[master .rb]) do |f|
          f.write(code)
          f.flush
          begin
            # WARNING: Pledge.pledge restricts the current process permanently.
            # In IO.popen context, this affects the parent process, not just the child.
            # On non-OpenBSD systems, this is a no-op.
            Pledge.unveil(f.path, "r")
            Pledge.pledge("stdio rpath")
          rescue StandardError => e
            # Not on OpenBSD
          end
          output = IO.popen([RbConfig::CONFIG['ruby_install_name'], f.path], err: %i[child out], &:read)
          { success: $CHILD_STATUS.success?, output: output, exit_code: $CHILD_STATUS.exitstatus }
        end
      end
    end
  end
end
