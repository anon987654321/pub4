# frozen_string_literal: true

require "yaml"
require "timeout"
require "rbconfig"

module MASTER
  module Stages
    class Intake
      def call(input)
        text = input[:text] || ""
        Result.ok(input.merge(text: text))
      end
    end

    class Compress
      COMPRESSION_FILE = File.join(__dir__, "..", "data", "compression.yml")

      class << self
        def patterns
          @patterns ||= load_patterns
        end

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

        self.class.patterns[:fillers].each do |pattern|
          text = text.gsub(pattern, "")
        end

        self.class.patterns[:phrases].each do |pattern|
          text = text.gsub(pattern, "")
        end

        text = text.gsub(/\s{2,}/, " ").strip
        compressed = original_length - text.length

        Result.ok(input.merge(text: text, bytes_compressed: compressed))
      end
    end

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

    class Route
      def call(input)
        text = input[:text] || ""
        tier = LLM.tier
        model = nil
        
        LLM::TIER_ORDER.each do |t|
          LLM.model_tiers[t]&.each do |m|
            if LLM.circuit_closed?(m)
              model = m
              break
            end
          end
          break if model
        end
        
        return Result.err("All models unavailable.") unless model

        Result.ok(input.merge(
          model: model,
          tier: tier,
          budget_remaining: LLM.budget_remaining,
        ))
      end
    end

    class Council
      def call(input)
        return Result.ok(input) unless input[:council]

        text = input[:text] || ""
        model = input[:model]
        return Result.ok(input) unless model

        review = Chamber.council_review(text, model: model)
        Result.ok(input.merge(
          council_verdict: review[:verdict],
          council_vetoed: review[:vetoed_by].any?,
          council_vetoes: review[:vetoed_by],
          council_votes: review[:votes],
        ))
      end
    end

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

          puts UI.dim("llm0: #{tokens_in}→#{tokens_out} tok, #{UI.currency_precise(cost)}")

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
            next
          end
        end

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

    class EnforceAxioms
      def call(input)
        code = input[:code] || input[:text] || input[:response] || ""
        return Result.ok(input) if code.empty?
        
        language = detect_language(input[:file_path] || input[:language])
        
        result = UniversalEnforce.enforce_on_code(
          code: code,
          language: language,
          path: input[:file_path]
        )
        
        if result.ok?
          violations = result.value[:violations]
          critical = violations.select { |v| v[:severity] == :error }
          
          if critical.any? && input[:strict_enforcement]
            return Result.err("Code violates #{critical.size} critical axioms")
          end
          
          Result.ok(input.merge(
            axiom_violations: violations,
            axiom_errors: critical.size,
            axiom_warnings: violations.count { |v| v[:severity] == :warn },
            enforced: true
          ))
        else
          Result.ok(input.merge(enforced: false, enforcement_error: result.error))
        end
      end
      
      private
      
      def detect_language(hint)
        case hint.to_s
        when /\.rb$/, /ruby/i then :ruby
        when /\.js$/, /javascript/i then :javascript
        when /\.py$/, /python/i then :python
        else :ruby
        end
      end
    end

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
            Pledge.unveil(f.path, "r")
            Pledge.pledge("stdio rpath")
          rescue StandardError
          end
          output = IO.popen([RbConfig.ruby, f.path], err: %i[child out], &:read)
          { success: $CHILD_STATUS.success?, output: output, exit_code: $CHILD_STATUS.exitstatus }
        end
      end
    end
  end
end
