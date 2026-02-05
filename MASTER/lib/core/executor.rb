# frozen_string_literal: true

module MASTER
  module Executor
    # Agentic command execution loop
    # Parses LLM responses for code blocks, executes safely, returns output

    SHELL_PATTERN = /```(?:sh|bash|shell|zsh)?\n(.*?)```/m
    RUBY_PATTERN = /```ruby\n(.*?)```/m
    MAX_OUTPUT = 4000
    MAX_CODE_PREVIEW = 100
    MAX_CODE_SHORT = 60

    class << self
      # Dry-run mode: show what would execute without running
      def dry_run?
        ENV['MASTER_DRY_RUN'] == '1' || @dry_run
      end

      def dry_run=(val)
        @dry_run = val
      end

      def process_response(response)
        results = []

        # Extract and execute shell commands
        response.scan(SHELL_PATTERN) do |match|
          code = match[0].strip
          next if code.empty?

          result = execute_shell(code)
          results << result if result
        end

        # Extract and execute Ruby code
        response.scan(RUBY_PATTERN) do |match|
          code = match[0].strip
          next if code.empty?

          result = execute_ruby(code)
          results << result if result
        end

        results
      end

      def execute_shell(command)
        # Block recursive self-invocation
        if command.match?(/\bbin\/cli\b|ruby.*master/i)
          Audit.log(command: command, type: :shell, status: :blocked) rescue nil
          return { type: :blocked, command: command, error: "Cannot invoke self recursively" }
        end

        # Dry-run mode
        if dry_run?
          return { type: :dry_run, command: command, output: "[DRY] would run: #{command[0..80]}" }
        end

        # Safety check first
        unless Safety.command_safe?(command)
          Audit.log(command: command, type: :shell, status: :blocked) rescue nil
          return { type: :blocked, command: command, error: "Blocked by safety filter" }
        end

        begin
          output = `#{command} 2>&1`
          status = $?.exitstatus
          Audit.log(command: command, type: :shell, status: status == 0 ? :ok : :err, output_length: output.length) rescue nil

          {
            type: :shell,
            command: command,
            output: truncate(output),
            status: status,
            success: status == 0
          }
        rescue => e
          { type: :shell, command: command, error: e.message, success: false }
        end
      end

      def execute_ruby(code)
        # Safety check
        unless Safety.ruby_safe?(code)
          Audit.log(command: code[0..MAX_CODE_PREVIEW], type: :ruby, status: :blocked) rescue nil
          return { type: :blocked, code: code[0..MAX_CODE_PREVIEW], error: "Blocked by safety filter" }
        end

        # Dry-run mode
        if dry_run?
          return { type: :dry_run, code: code[0..MAX_CODE_PREVIEW], output: "[DRY] would eval: #{code[0..MAX_CODE_SHORT]}..." }
        end

        begin
          # Execute in isolated binding
          result = eval(code, TOPLEVEL_BINDING.dup, "(master)", 1)
          Audit.log(command: code[0..MAX_CODE_PREVIEW], type: :ruby, status: :ok) rescue nil
          {
            type: :ruby,
            code: code[0..MAX_CODE_PREVIEW],
            result: truncate(result.inspect),
            success: true
          }
        rescue => e
          Audit.log(command: code[0..MAX_CODE_PREVIEW], type: :ruby, status: :err) rescue nil
          { type: :ruby, code: code[0..MAX_CODE_PREVIEW], error: e.message, success: false }
        end
      end

      def format_results(results)
        return nil if results.empty?

        results.map do |r|
          case r[:type]
          when :shell
            status = r[:success] ? "ok" : "err:#{r[:status]}"
            "#{status} #{r[:command][0..40]}\n#{r[:output]}"
          when :ruby
            status = r[:success] ? "ok" : "err"
            "#{status} ruby: #{r[:result] || r[:error]}"
          when :blocked
            "blocked: #{r[:error]}"
          end
        end.join("\n\n")
      end

      private

      def truncate(text)
        text.to_s[0..MAX_OUTPUT]
      end

      def trace(msg)
        ts = format('%07.3f', (Time.now.to_f * 1000) % 1000 / 1000.0)
        puts "    #{ts}  #{msg}"
      end
    end
  end
end
