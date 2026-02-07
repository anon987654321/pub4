# frozen_string_literal: true

module MASTER
  # AutoFixer - Automated code fixes with verification and rollback
  # Modes: conservative (whitespace only), moderate (+debug), aggressive (all)
  class AutoFixer
    MAX_FIXES_PER_RUN = 20
    MODES = %i[conservative moderate aggressive].freeze

    FIXERS = {
      trailing_whitespace: ->(code) { code.gsub(/[ \t]+$/, "") },
      debug_code: ->(code) { code.gsub(/^\s*(binding\.pry|debugger|byebug).*\n/, "") },
      puts_debug: ->(code) { code.gsub(/^\s*puts\s+["']debug.*["'].*\n/i, "") },
      empty_lines_excess: ->(code) { code.gsub(/\n{3,}/, "\n\n") },
      trailing_newlines: ->(code) { code.rstrip + "\n" },
      mixed_indentation: ->(code) { code.gsub(/^(\t+)/) { |m| "  " * m.length } },
      crlf_to_lf: ->(code) { code.gsub("\r\n", "\n") },
      bom_strip: ->(code) { code.sub(/\A\xEF\xBB\xBF/, "") },
    }.freeze

    MODE_FIXES = {
      conservative: %i[trailing_whitespace empty_lines_excess trailing_newlines crlf_to_lf bom_strip],
      moderate: %i[trailing_whitespace empty_lines_excess trailing_newlines puts_debug crlf_to_lf bom_strip mixed_indentation],
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

      fixable = violations&.select { |v| can_fix?(v[:type]) } || auto_detect(code)
      fixable = fixable.take(MAX_FIXES_PER_RUN)

      return Result.ok(file: file, fixed: 0, message: "No fixable violations") if fixable.empty?

      fixed_count = 0
      fixable.each do |violation|
        type = violation[:type]&.to_sym
        next unless can_fix?(type)

        fixer = FIXERS[type]
        next unless fixer

        new_code = fixer.call(code)
        if new_code != code
          code = new_code
          fixed_count += 1
          @fixes_applied << { file: file, type: type }
        end
      end

      return Result.ok(file: file, fixed: 0, message: "No changes needed") if code == original

      unless valid_syntax?(code, file)
        return Result.err("Fix produced invalid syntax - not writing")
      end

      File.write(file, code)

      Result.ok(
        file: file,
        fixed: fixed_count,
        types: @fixes_applied.select { |f| f[:file] == file }.map { |f| f[:type] }
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
        details: results.map { |r| r.ok? ? r.value : { error: r.error } }
      )
    end

    def fix_directory(dir, pattern: "**/*.rb")
      files = Dir.glob(File.join(dir, pattern))
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
      RubyVM::InstructionSequence.compile(code)
      true
    rescue SyntaxError
      false
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
      JSON.parse(code)
      true
    rescue StandardError
      false
    end
  end
end
