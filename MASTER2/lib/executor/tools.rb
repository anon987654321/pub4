# frozen_string_literal: true

module MASTER
  class Executor
    module Tools
      def execute_tool(action_str)
        # Sanitize input before processing
        action_str = sanitize_tool_input(action_str)
        return action_str if action_str.start_with?("BLOCKED:")

        case action_str
        when /^ask_llm\s+["']?(.+?)["']?\s*$/i
          ask_llm($1)

        when /^web_search\s+["']?([^"']+)["']?/i
          web_search($1)

        when /^browse_page\s+["']?(https?:\/\/[^\s"']+)["']?/i
          browse_page($1)

        when /^file_read\s+["']?([^"'\n]+)["']?/i
          file_read($1.strip)

        when /^file_write\s+["']?([^"'\n]+)["']?\s+["']?(.+)["']?/mi
          file_write($1.strip, $2)

        when /^analyze_code\s+["']?([^"'\n]+)["']?/i
          analyze_code($1.strip)

        when /^fix_code\s+["']?([^"'\n]+)["']?/i
          fix_code($1.strip)

        when /^shell_command\s+["']?([^"'\n]+)["']?/i
          shell_command($1)

        when /^code_execution.*```(\w*)?\n(.+?)```/mi
          code_execution($2)

        when /^council_review\s+["']?(.+?)["']?\s*$/i
          council_review($1)

        when /^memory_search\s+["']?([^"']+)["']?/i
          memory_search($1)

        when /^self_test/i
          self_test

        else
          "Unknown tool. Available: #{TOOLS.keys.join(', ')}"
        end
      rescue StandardError => e
        "Tool error: #{e.message}"
      end

      # Tool implementations

      def ask_llm(prompt)
        result = LLM.ask(prompt, tier: :fast)
        result.ok? ? result.value[:content][0..1000] : "LLM error: #{result.error}"
      end

      def web_search(query)
        if defined?(Web)
          result = Web.browse("https://duckduckgo.com/html/?q=#{URI.encode_www_form_component(query)}")
          result.ok? ? result.value[:content] : "Search failed: #{result.error}"
        else
          "Web module not available"
        end
      end

      def browse_page(url)
        if defined?(Web)
          result = Web.browse(url)
          result.ok? ? result.value[:content] : "Browse failed: #{result.error}"
        else
          # Validate URL first to prevent injection
          begin
            uri = URI.parse(url)
            unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
              return "Invalid URL: must be http or https"
            end
          rescue URI::InvalidURIError
            return "Invalid URL format"
          end

          # Use Open3.capture3 with array form to prevent shell injection
          stdout, stderr, status = Open3.capture3("curl", "-sL", "--max-time", "10", url)
          stdout[0..2000]
        end
      end

      def file_read(path)
        return "File not found: #{path}" unless File.exist?(path)
        content = File.read(path)
        content.length > 3000 ? "#{content[0..3000]}... (truncated, #{content.length} chars total)" : content
      end

      def file_write(path, content)
        expanded = File.expand_path(path)

        # Check protected paths first
        PROTECTED_WRITE_PATHS.each do |protected|
          # For absolute paths, compare directly; for relative, expand from root
          protected_expanded = if protected.start_with?("/")
            protected
          else
            File.expand_path(protected, MASTER.root)
          end

          if expanded.start_with?(protected_expanded) || expanded == protected_expanded
            return "BLOCKED: file_write to protected path '#{path}'"
          end
        end

        # Check working directory constraint
        cwd = File.expand_path(".")
        unless expanded.start_with?(cwd)
          return "BLOCKED: file_write path '#{path}' is outside working directory"
        end

        FileUtils.mkdir_p(File.dirname(expanded))
        File.write(expanded, content)
        "Written #{content.length} bytes to #{path}"
      end

      def analyze_code(path)
        return "File not found: #{path}" unless File.exist?(path)
        code = File.read(path)

        if defined?(CodeReview)
          result = CodeReview.analyze(code, filename: File.basename(path))
          "Issues: #{result[:issues].size}, Score: #{result[:score]}/#{result[:max_score]}, Grade: #{result[:grade]}"
        else
          "CodeReview module not available"
        end
      end

      def fix_code(path)
        if defined?(AutoFixer)
          fixer = AutoFixer.new(mode: :moderate)
          result = fixer.fix(path)
          result.ok? ? "Fixed #{result.value[:fixed]} issues in #{path}" : "Fix failed: #{result.error}"
        else
          "AutoFixer module not available"
        end
      end

      def shell_command(cmd)
        if DANGEROUS_PATTERNS.any? { |p| p.match?(cmd) }
          return "BLOCKED: dangerous shell command rejected"
        end

        if defined?(Constitution)
          check = Constitution.check_operation(:shell_command, command: cmd)
          return "BLOCKED: #{check.error}" unless check.ok?
        end

        if defined?(Shell)
          result = Shell.execute(cmd)
          output = result.ok? ? result.value : "Error: #{result.error}"
        else
          stdout, stderr, status = Open3.capture3(cmd)
          output = status.success? ? stdout : "Error: #{stderr}"
        end

        output.length > 1000 ? "#{output[0..1000]}... (truncated)" : output
      end

      def code_execution(code)
        # Block dangerous Ruby constructs
        dangerous_code = [
          /system\s*\(/,
          /exec\s*\(/,
          /`[^`]*`/,
          /Kernel\.exec/,
          /IO\.popen/,
          /Open3/,
          /FileUtils\.rm_rf/
        ]

        if dangerous_code.any? { |pattern| pattern.match?(code) }
          return "BLOCKED: code_execution contains dangerous constructs"
        end

        # Attempt Pledge sandboxing on OpenBSD if available
        if defined?(Pledge)
          begin
            Pledge.pledge("stdio rpath")
          rescue StandardError => e
            # Pledge not available or failed, continue without it
          end
        end

        stdout, stderr, status = Open3.capture3(RbConfig.ruby, stdin_data: code)
        status.success? ? stdout[0..500] : "Error: #{stderr[0..300]}"
      end

      def council_review(text)
        if defined?(Council)
          result = Council.council_review(text)
          "Passed: #{result[:passed]}, Consensus: #{result[:consensus]}, Votes: #{result[:votes].size}"
        else
          "Council module not available"
        end
      end

      def memory_search(query)
        if defined?(Memory)
          results = Memory.search(query, limit: 3)
          results.empty? ? "No memories found for: #{query}" : results.join("\n")
        else
          "Memory module not available"
        end
      end

      def self_test
        if defined?(SelfTest)
          result = SelfTest.run
          result.ok? ? result.value : "introspect failed: #{result.error}"
        else
          "Introspection module not available"
        end
      end

      def sanitize_tool_input(action_str)
        if DANGEROUS_PATTERNS.any? { |p| p.match?(action_str) }
          return "BLOCKED: dangerous pattern detected in tool input"
        end
        action_str
      end

      def check_tool_permission(tool_name)
        if defined?(Constitution)
          unless Constitution.permission?(tool_name)
            return Result.err("Tool '#{tool_name}' not permitted by constitution")
          end
        end
        Result.ok
      end

      def record_history(entry)
        @history << entry
        @history.shift if @history.size > MAX_HISTORY_ENTRIES
      end
    end
  end
end
