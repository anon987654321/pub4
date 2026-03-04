# frozen_string_literal: true

module MASTER
  module Scan
    module Rules
      # CodeStyle -- flags namespace inconsistencies, mixed symbol/string access,
      # missing dirty-flag on mutation, and ASCII decoration comments.
      # Migrated from Review::Scanner::CHECKS.
      module CodeStyle
        include Scan::Rule

        CHECKS = {
          namespace_prefix: {
            pattern:  /^(?!.*MASTER::)(DB|LLM|Session|Pipeline)\./,
            message:  "Use MASTER:: prefix for module references in bin/ scripts",
            severity: :critical,
          }.freeze,
          symbol_string_fallback: {
            pattern:  /\[["'][a-z_]+["']\]\s*\|\|\s*\[:[a-z_]+\]/,
            message:  "Mixed string/symbol access - use symbolize_names: true in JSON.parse",
            severity: :major,
          }.freeze,
          dirty_flag_missing: {
            pattern:  /\.pop\(\s*\)|\.shift\(|\.delete(?!_)|\.clear(?!\s*#.*dirty)/,
            message:  "Mutation without @dirty = true - changes won't persist",
            severity: :major,
          }.freeze,
          ascii_decoration: {
            pattern:  /^#\s*[-=]{3,}/,
            message:  "ASCII decoration comment adds visual noise -- use plain # Section header",
            severity: :minor,
          }.freeze,
        }.freeze

        def self.check(code, path: nil)
          findings = []

          code.each_line.with_index(1) do |line_text, line_num|
            CHECKS.each do |check_name, check_def|
              next unless line_text.match?(check_def[:pattern])

              findings << {
                rule:      check_name,
                name:      check_name,
                message:   check_def[:message],
                line:      line_num,
                severity:  check_def[:severity],
                autofix:   false,
                principle: nil,
              }
            end
          end

          findings
        end
      end
    end
  end
end
