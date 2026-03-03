# frozen_string_literal: true

module MASTER
  module Review
    class Fixer
      MAX_FIXES_PER_RUN = 20
      MODES = %i[conservative moderate aggressive].freeze

      FIXERS = {
        trailing_whitespace: ->(code) { code.gsub(/[ \t]+$/, "") },
        debug_code: ->(code) { code.gsub(/^\s*(binding\.pry|debugger|byebug).*\n/, "") },
        puts_debug: ->(code) { code.gsub(/^\s*puts\s+["']debug.*["'].*\n/i, "") },
        empty_lines_excess: ->(code) { code.gsub(/\n{3,}/, "\n\n") },
        trailing_newlines: ->(code) { "#{code.rstrip}\n" },
        mixed_indentation: ->(code) { code.gsub(/^(\t+)/) { |m| "  " * m.length } },
        crlf_to_lf: ->(code) { code.gsub("\r\n", "\n") },
        bom_strip: ->(code) { code.sub(/\A\xEF\xBB\xBF/, "") },
        # Language axiom auto-fixes
        freeze_constants: ->(code) {
          code.gsub(/^(\s*[A-Z][A-Z_]*\s*=\s*[\[{].*)$/m) do |m|
            m.include?(".freeze") ? m : "#{m.rstrip}.freeze"
          end
        },
        safe_navigation: ->(code) {
          code.gsub(/(\w+)\s*&&\s*\1\.(\w+)/) do
            "#{Regexp.last_match(1)}&.#{Regexp.last_match(2)}"
          end
        },
      }.freeze

      MODE_FIXES = {
        conservative: %i[trailing_whitespace empty_lines_excess trailing_newlines crlf_to_lf bom_strip],
        moderate: %i[trailing_whitespace empty_lines_excess trailing_newlines puts_debug crlf_to_lf bom_strip
                     mixed_indentation],
        aggressive: FIXERS.keys,
      }.freeze

      def initialize(mode: :conservative)
        @mode = MODES.include?(mode) ? mode : :conservative
        @fixes_applied = []
        @backups = {}
      end

      attr_reader :fixes_applied, :mode

      def fix(file, violations = nil)
        return Result.err("File not found: #{file}") unless File.exist?(file)

        code = File.read(file)
        original = code.dup
        @backups[file] = original

        all_violations = violations || auto_detect(code)
        rule_fixable   = all_violations.select { |v| can_fix?(v[:type]) }.take(MAX_FIXES_PER_RUN)
        llm_fixable    = all_violations.reject { |v| can_fix?(v[:type]) }
                                       .select { |v| llm_strategies_for(v[:axiom_id] || v[:type]).any? }

        fixed_count = 0

        rule_fixable.each do |violation|
          type = violation[:type]&.to_sym
          fixer = FIXERS[type]
          next unless fixer

          new_code = fixer.call(code)
          next unless new_code != code

          code = new_code
          fixed_count += 1
          @fixes_applied << { file: file, type: type }
        end

        llm_fixable.first(3).each do |violation|
          result = llm_fix(code, violation, filename: file)
          next unless result.ok?

          new_code = result.value[:code]
          next unless new_code != code && valid_syntax?(new_code, file)

          code = new_code
          fixed_count += 1
          @fixes_applied << { file: file, type: :llm, axiom: violation[:axiom_id], strategies: result.value[:strategies] }
        end

        return Result.ok(file: file, fixed: 0, message: "No changes needed") if code == original

        return Result.err("Fix produced invalid syntax - not writing.") unless valid_syntax?(code, file)

        File.write(file, code)

        Result.ok(
          file: file,
          fixed: fixed_count,
          types: @fixes_applied.select { |f| f[:file] == file }.map { |f| f[:type] },
        )
      end

      def fix_all(files, violations_by_file = {})
        results = []

        files.each do |file|
          violations = violations_by_file[file] || []
          result = fix(file, violations)
          results << result
        end

        successful = results.count(&:ok?)
        total_fixed = results.select(&:ok?).sum { |r| r.value[:fixed] }

        Result.ok(
          files_processed: files.size,
          files_fixed: successful,
          total_fixes: total_fixed,
          details: results.map { |r| r.ok? ? r.value : { error: r.error } },
        )
      end

      def fix_directory(dir, pattern: "**/*.rb")
        skip = defined?(Paths::SKIP_DIRS) ? Paths::SKIP_DIRS : %w[.git vendor tmp var node_modules .bundle coverage log dist]
        files = Dir.glob(File.join(dir, pattern)).reject { |f| skip.any? { |d| f.include?("/#{d}/") } }
        fix_all(files)
      end

      def rollback(file)
        return Result.err("No backup for #{file}") unless @backups[file]

        File.write(file, @backups[file])
        @backups.delete(file)

        Result.ok("Rolled back #{file}")
      end

      def rollback_all
        @backups.each do |file, content|
          File.write(file, content)
        end

        count = @backups.size
        @backups.clear
        @fixes_applied.clear

        Result.ok("Rolled back #{count} files")
      end

      private

      def can_fix?(type)
        type = type.to_sym
        allowed = MODE_FIXES[@mode] || []
        allowed.include?(type)
      end

      # Look up llm_strategies for an axiom_id from axioms.yml.
      # Returns array of strategy strings, e.g. ["extract_constant", "extract_method"]
      def llm_strategies_for(axiom_id)
        @axioms_cache ||= begin
          f = File.join(MASTER.root, "data", "axioms.yml")
          YAML.safe_load_file(f) rescue []
        end
        axiom = @axioms_cache.find { |a| a["id"] == axiom_id.to_s }
        axiom&.dig("llm_strategies") || []
      end

      # Ask the LLM to fix a violation, using llm_strategies as a hint.
      # Returns Result with :code (fixed source) or error.
      def llm_fix(code, violation, filename: "code")
        return Result.err("LLM not available") unless defined?(LLM)

        axiom_id  = violation[:axiom_id] || violation[:type]
        strategies = llm_strategies_for(axiom_id)
        strategy_hint = strategies.any? ? "Preferred strategies: #{strategies.join(", ")}." : ""

        prompt = <<~PROMPT
          Fix the following violation in this #{File.extname(filename).delete(".").upcase} code.
          Violation: #{violation[:message] || violation[:description] || axiom_id}
          #{strategy_hint}
          Return ONLY the corrected code, no explanations.

          ```
          #{code}
          ```
        PROMPT

        result = LLM.ask(prompt, tier: :fast)
        return result unless result.ok?

        fixed = result.value[:content].gsub(/\A```\w*\n/, "").gsub(/\n```\z/, "").strip
        Result.ok(code: fixed, strategies: strategies)
      end

      def auto_detect(code)
        violations = []

        violations << { type: :trailing_whitespace } if code =~ /[ \t]+$/
        violations << { type: :empty_lines_excess } if code =~ /\n{3,}/
        violations << { type: :trailing_newlines } if code =~ /\n\n+\z/
        violations << { type: :debug_code } if code =~ /\b(binding\.pry|debugger|byebug)\b/
        violations << { type: :puts_debug } if code =~ /^\s*puts\s+["']debug/i
        violations << { type: :mixed_indentation } if code =~ /^\t/
        violations << { type: :crlf_to_lf } if code.include?("\r\n")
        violations << { type: :bom_strip } if code.start_with?("\xEF\xBB\xBF")

        violations
      end

      def valid_syntax?(code, file)
        ext = File.extname(file).downcase
        case ext
        when ".rb"
          valid_ruby?(code)
        when ".yml", ".yaml"
          valid_yaml?(code)
        when ".json"
          valid_json?(code)
        else
          true
        end
      end

      def valid_ruby?(code)
        MASTER::Utils.valid_ruby?(code)
      end

      def valid_yaml?(code)
        require "yaml"
        YAML.safe_load(code)
        true
      rescue StandardError
        false
      end

      def valid_json?(code)
        require "json"
        JSON.parse(code, symbolize_names: true)
        true
      rescue StandardError
        false
      end
    end
  end
end
