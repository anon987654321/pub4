# frozen_string_literal: true

require "open3"
require "rbconfig"

module MASTER
  class Executor
    # Tool implementations - All available tools for the executor
    module Tools
      def ask_llm(prompt)
        result = LLM.ask(prompt, tier: :fast)
        result.ok? ? result.value[:content][0..MAX_LLM_RESPONSE_PREVIEW] : "LLM error: #{result.error}"
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
          # Fix: Use Open3 with proper escaping to prevent shell injection
          stdout, _, _ = Open3.capture3("curl", "-sL", "--max-time", "10", url)
          stdout[0..MAX_CURL_CONTENT]
        end
      end

      def file_read(path)
        return "File not found: #{path}" unless File.exist?(path)
        content = File.read(path)
        content.length > MAX_FILE_CONTENT ? "#{content[0..MAX_FILE_CONTENT]}... (truncated, #{content.length} chars total)" : content
      end

      def file_write(path, content)
        expanded = File.expand_path(path)
        
        # Fix: Add explicit canonicalization to prevent path traversal
        begin
          real_cwd = File.realpath(".")
          unless expanded.start_with?(real_cwd)
            return "BLOCKED: file_write path '#{path}' is outside working directory"
          end
        rescue Errno::ENOENT
          # If realpath fails, fall back to expand_path check
          cwd = File.expand_path(".")
          unless expanded.start_with?(cwd)
            return "BLOCKED: file_write path '#{path}' is outside working directory"
          end
        end
        
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

        output.length > MAX_SHELL_OUTPUT ? "#{output[0..MAX_SHELL_OUTPUT]}... (truncated)" : output
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
          rescue StandardError
            # Pledge not available or failed, continue without it
          end
        end
        
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, stdin_data: code)
        status.success? ? stdout[0..500] : "Error: #{stderr[0..300]}"
      end

      def council_review(text)
        if defined?(Chamber)
          result = Chamber.council_review(text)
          "Passed: #{result[:passed]}, Consensus: #{result[:consensus]}, Votes: #{result[:votes].size}"
        else
          "Chamber module not available"
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
          result.ok? ? "Self-test completed" : "Self-test failed: #{result.error}"
        else
          "SelfTest module not available"
        end
      end
    end
  end
end
