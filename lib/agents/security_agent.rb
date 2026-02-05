# frozen_string_literal: true

module Master
  module Agents
    class SecurityAgent < BaseAgent
      SECURITY_PATTERNS = [
        { pattern: /eval\s*\(/i, severity: :critical, message: "Use of eval() detected - code injection risk" },
        { pattern: /system\s*\(/i, severity: :critical, message: "Use of system() - command injection risk" },
        { pattern: /exec\s*\(/i, severity: :critical, message: "Use of exec() - command injection risk" },
        { pattern: /`[^`]+`/, severity: :high, message: "Backtick command execution detected" },
        { pattern: /File\.read\([^)]*params/i, severity: :high, message: "File read with user input - path traversal risk" },
        { pattern: /password\s*=\s*["'][^"']+["']/i, severity: :critical, message: "Hardcoded password detected" },
        { pattern: /api[_-]?key\s*=\s*["'][^"']+["']/i, severity: :critical, message: "Hardcoded API key detected" },
        { pattern: /secret\s*=\s*["'][^"']+["']/i, severity: :high, message: "Hardcoded secret detected" },
        { pattern: /\.constantize/i, severity: :high, message: "Use of constantize() - code injection risk" },
        { pattern: /\.send\s*\(/i, severity: :medium, message: "Dynamic method invocation with send()" },
        { pattern: /sql\s*=\s*["'].*#\{/i, severity: :critical, message: "SQL injection risk - string interpolation in query" },
        { pattern: /\.html_safe/i, severity: :medium, message: "html_safe bypasses XSS protection" }
      ].freeze

      def analyze(code, file_path = nil)
        clear_findings
        
        # Pattern-based security checks
        code.lines.each_with_index do |line, idx|
          SECURITY_PATTERNS.each do |pattern_info|
            if line.match?(pattern_info[:pattern])
              add_finding(
                severity: pattern_info[:severity],
                category: :security,
                message: pattern_info[:message],
                line: idx + 1,
                suggestion: suggest_fix(pattern_info[:pattern], line)
              )
            end
          end
        end

        # LLM-based deep security analysis for critical files
        if should_deep_scan?(code, file_path)
          perform_deep_security_scan(code, file_path)
        end

        @findings
      end

      private

      def should_deep_scan?(code, file_path)
        # Deep scan if patterns found or file handles sensitive operations
        return true if @findings.any? { |f| f[:severity] == :critical }
        return true if file_path&.match?(/auth|session|user|admin|payment|credential/i)
        return true if code.match?(/password|token|secret|key|credential/i)
        false
      end

      def perform_deep_security_scan(code, file_path)
        prompt = <<~PROMPT
          Perform a security audit of this code. Focus on:
          1. Injection vulnerabilities (SQL, command, code)
          2. Authentication/authorization issues
          3. Sensitive data exposure
          4. Cryptographic failures
          5. Insecure configurations

          File: #{file_path || "unknown"}
          Code (first 1000 chars):
          ```
          #{code[0..1000]}
          ```

          Return JSON array of issues: [{"severity": "critical|high|medium|low", "line": num, "issue": "...", "fix": "..."}]
        PROMPT

        analysis = analyze_with_llm(prompt, tier: :code)
        
        if analysis
          # Parse LLM response and add findings
          begin
            issues = JSON.parse(analysis.match(/\[.*\]/m).to_s)
            issues.each do |issue|
              add_finding(
                severity: issue["severity"]&.to_sym || :medium,
                category: :security,
                message: issue["issue"],
                line: issue["line"],
                suggestion: issue["fix"]
              )
            end
          rescue
            # If parsing fails, add raw analysis as a finding
            add_finding(
              severity: :info,
              category: :security,
              message: "LLM Security Analysis: #{analysis[0..200]}...",
              suggestion: "Review full analysis for details"
            )
          end
        end
      end

      def suggest_fix(pattern, line)
        case pattern.source
        when /eval/i
          "Replace eval() with safer alternatives like JSON.parse() or a proper parser"
        when /system|exec/i
          "Use Process.spawn with explicit arguments or sanitize input thoroughly"
        when /password|secret|key/i
          "Move secrets to environment variables or secure configuration"
        when /sql.*\#\{/i
          "Use parameterized queries or an ORM with prepared statements"
        else
          "Review security implications and use safer alternatives"
        end
      end
    end
  end
end
