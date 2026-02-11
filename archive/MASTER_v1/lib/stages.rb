# frozen_string_literal: true

module MASTER
  module Stages
    # Pass text through, load persona if specified
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

    # Block dangerous commands
    class Guard
      DENY = [
        /rm\s+-r[f]?\s+\//, />\s*\/dev\/[sh]da/, /DROP\s+TABLE/i,
        /FORMAT\s+[A-Z]:/i, /mkfs\./, /dd\s+if=/
      ].freeze

      def call(input)
        text = input[:text] || ""
        match = DENY.find { |p| p.match?(text) }
        match ? Result.err("Blocked: dangerous pattern detected") : Result.ok(input)
      end
    end

    # Select model via circuit breaker + budget
    class Route
      def call(input)
        text = input[:text] || ""
        selected = LLM.select_model(text.length)
        return Result.err("All models unavailable") unless selected
        Result.ok(input.merge(model: selected[:model], tier: selected[:tier], budget_remaining: LLM.remaining))
      end
    end

    # Call LLM, stream to stderr, record cost
    class Ask
      def call(input)
        model = input[:model] || "deepseek-r1"
        chat = LLM.chat(model: model)
        persona = input[:persona_instructions]
        chat.with_instructions(persona) if persona && chat.respond_to?(:with_instructions)

        begin
          response = chat.ask(input[:text]) do |chunk|
            $stderr.print chunk.content if chunk.content
          end
          $stderr.puts

          tokens_in = response.input_tokens rescue 0
          tokens_out = response.output_tokens rescue 0
          LLM.record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)
          LLM.record_success(model)

          Result.ok(input.merge(response: response.content, tokens_in: tokens_in, tokens_out: tokens_out))
        rescue => e
          LLM.record_failure(model)
          Result.err("LLM error (#{model}): #{e.message}")
        end
      end
    end

    # Format output: typeset prose, preserve code blocks byte-for-byte
    class Render
      CODE_FENCE = /^```/

      def call(input)
        text = input[:response] || ""
        Result.ok(input.merge(rendered: typeset_safe(text)))
      end

      private

      def typeset_safe(text)
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

        regions.map { |r| r[:code] ? r[:text] : typeset_prose(r[:text]) }.join
      end

      def typeset_prose(text)
        text.gsub(/"([^"]*?)"/) { "\u201C#{$1}\u201D" }
            .gsub(/\s--\s/, " \u2014 ")
            .gsub(/\.\.\./, "\u2026")
      end
    end

    # Self-modification: git snapshot → write → test → rollback on failure
    class Evolve
      def call(input)
        file = input[:file]
        return Result.err("No file specified") unless file && File.exist?(file)

        content = input[:response]
        return Result.err("No content to write") unless content

        before = IO.popen(%w[git stash create], &:read).strip
        File.write(file, content)

        test_cmd = input[:test_command] || "bundle exec ruby -Ilib:test test/"
        test_output = IO.popen(test_cmd, err: [:child, :out], &:read)
        passed = $?.success?

        unless passed
          system("git", "checkout", "--", file) if before.empty?
          IO.popen(["git", "stash", "apply", before], &:read) unless before.empty?
        end

        Result.ok(input.merge(modified: true, tests_passed: passed, rolled_back: !passed, test_output: test_output))
      rescue => e
        Result.err("Evolve failed: #{e.message}")
      end
    end

    # Sandboxed Ruby execution (pledge on OpenBSD)
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
          f.write(code); f.flush
          begin
            Pledge.unveil(f.path, "r")
            Pledge.pledge("stdio rpath")
          rescue Pledge::Error
            # Not on OpenBSD — proceed unsandboxed
          end
          output = IO.popen(["ruby", f.path], err: [:child, :out], &:read)
          { success: $?.success?, output: output, exit_code: $?.exitstatus }
        end
      end
    end
  end
end
