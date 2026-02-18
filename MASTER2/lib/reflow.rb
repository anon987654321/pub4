# frozen_string_literal: true

module MASTER
  # Reflow - Reorder any code or content by importance and chronology
  # Part of 4-phase file processing: Clean -> Rename/Rephrase -> Structural Transform -> Expand/Contract
  module Reflow
    # Universal ordering principles (language-agnostic)
    IMPORTANCE_ORDER = [
      :meta,          # Shebang, magic comments, frontmatter
      :imports,       # Requires, imports, includes, use statements
      :types,         # Type definitions, interfaces, structs
      :constants,     # Constants, enums, static values
      :public_api,    # Public functions, exported methods
      :internal,      # Internal/protected functions
      :private,       # Private helpers
      :tests,         # Test code
    ].freeze

    # Language detection patterns
    LANGUAGE_PATTERNS = {
      ruby: /\.rb$/,
      javascript: /\.(js|jsx|mjs)$/,
      typescript: /\.(ts|tsx)$/,
      go: /\.go$/,
      rust: /\.rs$/,
      markdown: /\.(md|markdown)$/,
      yaml: /\.(yml|yaml)$/,
      html: /\.(html|htm)$/,
      css: /\.(css|scss|sass)$/,
    }.freeze

    class << self
      # Analyze any file and suggest reflow
      def analyze(content, filename: "file")
        lang = detect_language(filename)
        sections = extract_sections(content, lang)
        issues = check_ordering(sections)

        { filename: filename, language: lang, issues: issues, sections: sections }
      end

      # Reflow any file (returns new content)
      def reflow(content, filename: "file")
        lang = detect_language(filename)
        sections = extract_sections(content, lang)

        # Sort by importance
        sorted = sections.sort_by { |s| IMPORTANCE_ORDER.index(s[:type]) || 999 }

        # Rebuild with proper spacing
        result = []
        sorted.each_with_index do |section, idx|
          result << "\n" if idx > 0 && needs_blank_line?(sections[idx - 1], section)
          result.concat(section[:lines])
        end

        result.join
      end

      # Batch reflow directory
      def reflow_directory(path, dry_run: true)
        patterns = %w[*.rb *.py *.js *.ts *.go *.rs *.md *.yml *.yaml]
        files = patterns.flat_map { |p| Dir.glob(File.join(path, "**", p)) }
        changes = []

        files.each do |file|
          content = File.read(file)
          analysis = analyze(content, filename: file)

          next if analysis[:issues].empty?

          if dry_run
            changes << { file: file, issues: analysis[:issues].size, language: analysis[:language] }
          else
            new_content = reflow(content, filename: file)
            if new_content != content
              File.write(file, new_content)
              changes << { file: file, reflowed: true }
            end
          end
        end

        { files_checked: files.size, changes: changes }
      end

      private

      def detect_language(filename)
        LANGUAGE_PATTERNS.find { |lang, pattern| filename.match?(pattern) }&.first || :unknown
      end

      def extract_sections(content, lang)
        case lang
        when :ruby then extract_ruby_sections(content)
        when :javascript, :typescript then extract_js_sections(content)
        when :go then extract_go_sections(content)
        when :markdown then extract_markdown_sections(content)
        when :yaml then extract_yaml_sections(content)
        else extract_generic_sections(content)
        end
      end

      def extract_ruby_sections(content)
        sections = []
        current = { type: :unknown, lines: [] }
        visibility = :public_api

        content.each_line do |line|
          type = case line.strip
                 when /^#!/ then :meta
                 when /^#\s*(frozen_string_literal|encoding)/ then :meta
                 when /^require/ then :imports
                 when /^[A-Z][A-Z0-9_]*\s*=/ then :constants
                 when /^(module|class)\s/ then :types
                 when "private" then visibility = :private; nil
                 when "protected" then visibility = :internal; nil
                 when /^def\s+self\./ then :public_api
                 when /^def\s/ then visibility
                 else nil
                 end

          if type && type != current[:type]
            add_section(sections, current)
            current = { type: type, lines: [] }
          end
          current[:lines] << line
        end

        add_section(sections, current)
        sections
      end

      def extract_js_sections(content)
        sections = []
        current = { type: :unknown, lines: [] }

        content.each_line do |line|
          type = case line.strip
                 when /^['"]use strict['"]/ then :meta
                 when /^\/\*\*/ then :meta  # JSDoc
                 when /^(import|require)\s/ then :imports
                 when /^(const|let|var)\s+[A-Z][A-Z0-9_]*\s*=/ then :constants
                 when /^(interface|type)\s/ then :types
                 when /^(class|function)\s/ then :public_api
                 when /^export\s/ then :public_api
                 when /^(const|let|var)\s+_/ then :private
                 else nil
                 end

          if type && type != current[:type]
            add_section(sections, current)
            current = { type: type, lines: [] }
          end
          current[:lines] << line
        end

        add_section(sections, current)
        sections
      end

      def extract_go_sections(content)
        sections = []
        current = { type: :unknown, lines: [] }

        content.each_line do |line|
          type = case line.strip
                 when /^package\s/ then :meta
                 when /^import\s/ then :imports
                 when /^(type|struct|interface)\s/ then :types
                 when /^const\s/ then :constants
                 when /^func\s+[A-Z]/ then :public_api  # Exported (uppercase)
                 when /^func\s+[a-z]/ then :private     # Unexported (lowercase)
                 else nil
                 end

          if type && type != current[:type]
            add_section(sections, current)
            current = { type: type, lines: [] }
          end
          current[:lines] << line
        end

        add_section(sections, current)
        sections
      end

      def extract_markdown_sections(content)
        # For markdown: frontmatter -> h1 -> h2 -> h3 -> content
        sections = []
        current = { type: :unknown, lines: [] }
        in_frontmatter = false

        content.each_line do |line|
          if line.strip == "---"
            in_frontmatter = !in_frontmatter
            type = :meta
          elsif in_frontmatter
            type = :meta
          else
            type = case line
                   when /^#\s/ then :public_api      # h1 = main content
                   when /^##\s/ then :internal       # h2 = subsections
                   when /^###/ then :private         # h3+ = details
                   else nil
                   end
          end

          if type && type != current[:type]
            add_section(sections, current)
            current = { type: type, lines: [] }
          end
          current[:lines] << line
        end

        add_section(sections, current)
        sections
      end

      def extract_yaml_sections(content)
        # YAML: comments at top, then keys by importance
        sections = []
        current = { type: :unknown, lines: [] }

        content.each_line do |line|
          type = case line
                 when /^#/ then :meta
                 when /^[a-z_]+:/ then :public_api
                 else nil
                 end

          if type && type != current[:type]
            add_section(sections, current)
            current = { type: type, lines: [] }
          end
          current[:lines] << line
        end

        add_section(sections, current)
        sections
      end

      def extract_generic_sections(content)
        [{ type: :unknown, lines: content.lines }]
      end

      def check_ordering(sections)
        issues = []
        types = sections.map { |s| s[:type] }.reject { |t| t == :unknown }
        expected = types.sort_by { |t| IMPORTANCE_ORDER.index(t) || 999 }

        if types != expected
          issues << {
            type: :section_order,
            message: "Sections out of importance order",
            current: types,
            expected: expected,
          }
        end

        issues
      end

      def needs_blank_line?(prev_section, curr_section)
        return false unless prev_section
        prev_section[:type] != curr_section[:type]
      end

      # Helper to add section to list only if it has content
      def add_section(sections, section)
        sections << section unless section[:lines].empty?
      end
    end
  end
end

