# frozen_string_literal: true

module Master
  module Judge
    module Scan
      module Rules

      # SQL strings embedded in Ruby DB adapter files are expected — only flag
      # actual mixed-medium template files.
        RuleDSL.rule :NO_MULTIPLE_LANGUAGES,
          severity: :warning, tags: %i[SMALL_PARTS],
          description: "one medium per artifact" do |src, path:|
          next [] if path.to_s.include?("/judge/scan/rules/")
          scan_lines(src, /<%|<script\b|<style\b/,
            message: "mixed medium — extract to a dedicated file")
        end

        RuleDSL.rule :SAFE_NAVIGATION,
          severity: :warning, tags: %i[READABILITY],
          description: "use null-safe navigation over nil-guard && chains" do |src, path:|
          next [] if path.to_s.include?("/judge/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            next unless line.match?(/(\w+)\s*&&\s*\1\.\w+/)
            next if line.match?(/[!=<>]=|[<>]|\?\s*\w/)
            finding(line: n, message: "nil-guard chain — use safe navigation (&.) or (?.) instead")
          end
        end

        RuleDSL.rule :FEW_ARGUMENTS,
          severity: :warning, tags: %i[SMALL_PARTS],
          description: "ideal is zero to two positional arguments" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, n|
            next unless line.match?(/\bdef\s+\w+\(/)
            args = line[/\(([^)]*)\)/, 1].to_s.split(",").map(&:strip)
            positional = args.reject { |arg| arg.empty? || arg.start_with?("*", "&") || arg.include?(":") || arg.include?("=") }
            finding(line: n, message: "3+ positional args — use keyword arguments or a value object") if positional.size >= 3
          end
        end

        RuleDSL.rule :N_PLUS_ONE,
          severity: :warning, tags: %i[PERFORMANCE],
          description: "loading records one-by-one inside a loop" do |src, path:|
          # Only meaningful in Rails app/ trees; non-AR enumerable chains are fine.
          next [] unless path.match?(%r{/app/|/spec/|/test/})
          scan_lines(src, /\.(each|map|collect)\s*(do|\{).*\.\w+\.\w+/,
            message: "N+1 query candidate — use includes/eager_load")
        end

      # Only positional boolean defaults are flag arguments. Keyword defaults
      # (stream: false, enabled: true) are not — they're fine API design.
        RuleDSL.rule :NO_FLAG_ARGUMENTS,
          severity: :warning, tags: %i[SMALL_PARTS],
          description: "a flag that selects behavior means two things hiding as one" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, n|
            next unless line.match?(/def \w+\(/)
            args_str = line[/\(([^)]*)\)/, 1].to_s
            args = args_str.split(",").map(&:strip)
            positional_bool = args.any? do |a|
              a.match?(/\A\w+\s*=\s*(true|false)\z/) && !a.include?(":")
            end
            finding(line: n, message: "boolean flag arg — split into two methods") if positional_bool
          end
        end

      # Exclude numeric dot-chains (IP addresses, version numbers) and stdlib
      # transformation chains (.to_s.strip.empty?) which are idiomatic Ruby.
        RuleDSL.rule :LAW_OF_DEMETER,
          severity: :warning, tags: %i[COUPLING],
          description: "only talk to immediate friends" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, n|
            next if line.strip.start_with?("#")
            next unless line.match?(/\b[a-z_]\w*(?:\.[a-z_]\w*){3}/)
            next if line.match?(/\d+\.\d+\.\d+\.\d+/)
            next if line.match?(/\.(to_s|to_i|to_f|to_a|to_h|strip|chomp|compact|first|last|join)\b/) ||
                    line.match?(/\.(empty\?|any\?|size|length)\b/)
            stripped = line.gsub(/["'][^"']*["']/, '""').gsub(/\(.*?\)/, "()")
            next unless stripped.match?(/\b[a-z_]\w*(?:\.[a-z_]\w*){3}/)
            finding(line: n, message: "4-level chain — introduce a local variable or delegation")
          end
        end

      # Generic names: only very short or clearly placeholder names. `data` and
      # `result` are contextually meaningful in most Ruby code.
        RuleDSL.rule :MEANINGFUL_NAMES,
          severity: :info, tags: %i[READABILITY],
          description: "names reveal intent" do |src, path:|
          scan_lines(src, /\b(tmp|temp|data|result|val|ret|obj|str|arr|buf)\b\s*=/,
            message: "generic name — use a name that reveals intent")
        end

        RuleDSL.rule :WHY_NOT_WHAT,
          severity: :info, tags: %i[BE_CONCISE],
          description: "comments explain why, not what" do |src, path:|
          scan_lines(src, /#\s*(increment|set|get|update|return|initialize|create|add)\s+\w+/,
            message: "comment describes what the code does — explain why instead")
        end

        RuleDSL.rule :TYPOGRAPHIC_EXCELLENCE,
          severity: :info, tags: %i[TYPOGRAPHY],
          description: "typographic excellence in user-facing text" do |src, path:|
          next [] if path.to_s.include?("/judge/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            next if line.match?(/Open3|capture2|capture3|gsub\(|Shellwords/)
            next if line.match?(/,\s*"--"\s*,|,\s*"--"\s*\)|<<\s*["']--/)
            next unless line.match?(/["']\.\.\.[\"']|["']--["']/)
            finding(line: n, message: "ASCII typography — use Unicode ellipsis … and em dash —")
          end
        end

      # Exclude YAML document separators (---) and data file structural lines;
      # only flag decorative runs inside code comments or string literals.
        RuleDSL.rule :TYPOGRAPHY_DISCIPLINE,
          severity: :info, tags: %i[TYPOGRAPHY],
          description: "hierarchy via weight and brightness, not decoration" do |src, path:|
          next [] if path.to_s.include?("/judge/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            stripped = line.strip
            next if stripped == "---" || stripped.start_with?("---") && path.end_with?(".yml", ".yaml")
            next if stripped.start_with?("//", "/*", "*")
            next unless stripped.match?(/[-=]{4,}|[╭╮╰╯│─]/)
            finding(line: n, message: "ASCII decoration — use whitespace and typographic weight instead")
          end
        end

        RuleDSL.rule :NULL_BLINDNESS,
          severity: :error, tags: %i[CORRECTNESS],
          description: "comparisons against nullable columns must use IS NULL" do |src, path:|
          next [] if path.to_s.include?("/judge/scan/rules/")
          scan_lines(src, /= NULL|!= NULL|== nil.*column|column.*== nil/,
            message: "NULL comparison — use IS NULL / IS NOT NULL in SQL; .nil? in Ruby")
        end

        RuleDSL.rule :SECRET_PROXIMITY,
          severity: :error, tags: %i[SECURITY],
          description: "secrets and consumers must not share a file" do |src, path:|
          scan_lines(src, /(password|secret|token|api_key|private_key)\s*=\s*['"][^'"]{8,}/,
            message: "hardcoded secret — move to environment variable or secrets manager")
        end

        RuleDSL.rule :MAGIC_COLOR,
          severity: :warning, tags: %i[MAINTAINABILITY],
          description: "color values must reference design tokens, not raw hex/rgb" do |src, path:|
          scan_lines(src, /#[0-9a-fA-F]{3,6}\b|rgb\(|rgba\(|hsl\(/,
            message: "raw color value — reference a CSS custom property or design token")
        end

      # `loop do` is legitimate for event loops and daemons. Only flag `retry`
      # without an obvious cap, and bare `while true` in library code.
        RuleDSL.rule :UNBOUNDED_RETRY,
          severity: :error, tags: %i[ROBUSTNESS],
          description: "retry loops must have a max_attempts cap and backoff" do |src, path:|
          next [] if path.to_s.include?("/judge/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            stripped = line.strip
            next if stripped.start_with?("#")
            next if stripped.match?(/loop\s*do/)
            next if stripped.match?(/retry\\/)
            next unless stripped.match?(/\bretry\b|while\s+true/)
            finding(line: n, message: "unbounded retry — add max_attempts cap and exponential backoff")
          end
        end

        RuleDSL.rule :ONE_SOURCE,
          severity: :warning, tags: %i[COUPLING],
          description: "constants defined locally when a canonical ONE_SOURCE exists" do |src, path:|
          next [] if path.to_s.include?("/judge/scan/rules/")
          next [] if path.to_s.include?("master.rb")
          patterns = [
            [/COUNCIL_PATH\s*=/, "define COUNCIL_PATH once in master.rb; reference Master::COUNCIL_PATH"],
            [/RULES_PATH\s*=/, "define RULES_PATH once in master.rb; reference Master::RULES_PATH"],
            [/DATA_DIR\s*=\s*File\.join.*\bdata\b/, "use Master::DATA constant"],
          ]
          src.each_line.with_index(1).flat_map do |line, n|
            patterns.filter_map { |re, msg| finding(line: n, message: msg) if re.match?(line) }
          end
        end

      # Bias: SIMULATION — future tense in output implies intent without evidence.
        RuleDSL.rule :SIMULATION,
          severity: :warning, tags: %i[ANTI_SIMULATION DENSITY],
          description: "future tense implies without evidence — use indicative past" do |src, path:|
          next [] unless path.to_s.end_with?(".rb", ".md", ".txt", ".erb")
          next [] if path.to_s.include?("/judge/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            next if line.strip.start_with?("#")
            next unless line.match?(/\b(will\s+\w+|would\s+\w+|let('s|\s+us)\s+\w+|I\s+will\s+|we\s+will\s+)/i)
            finding(line: n, message: "simulation language — rewrite in indicative past or present tense")
          end
        end

      # Bias: COMPLETION_THEATER — ellipsis/etc as placeholder outputs.
        RuleDSL.rule :COMPLETION_THEATER,
          severity: :error, tags: %i[ROBUSTNESS COMPLETENESS],
          description: "ellipsis or etcetera as placeholder violates completeness" do |src, path:|
          next [] if path.to_s.include?("/judge/scan/rules/")
          src.each_line.with_index(1).filter_map do |line, n|
            stripped = line.strip
            next if stripped.start_with?("#")
            next unless stripped.match?(/\.\.\.\s*$/) || stripped.match?(/\betc\.?\b|\betcetera\b/i)
            finding(line: n, message: "completion theater — implement or delete, never placeholder")
          end
        end

        RuleDSL.rule :SQL_INJECTION,
          severity: :error, tags: %i[SECURITY],
          description: "parameterize all SQL — never interpolate user input" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, n|
            stripped = line.strip
            next if stripped.start_with?("#")
            next unless stripped.match?(/\.(?:execute|query)\s*\(.*#\{/) ||
                        stripped.match?(/\.(?:execute|query)\s*\(\s*["'][^"']*\+\s*/)
            finding(line: n, message: "SQL injection risk — use parameterized queries or ActiveRecord helpers")
          end
        end

      # Detects 2+ spaces before hash rocket, assignment, or inline comment to
      # catch column-alignment padding. Skips heredocs, string content, and
      # lines that are themselves just operators.
        RuleDSL.rule :NO_COLUMN_ALIGN,
          severity: :info, tags: %i[DENSITY],
          description: "one space before operators — no column padding" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, n|
            stripped = line.strip
            next if stripped.start_with?("#", "//", "*")
            next if stripped.match?(/\A[-=]+\z/)
            next unless stripped.match?(/\S {2,}(?:=>|[^=!<>]=[^=>]|:\s)/)
            finding(line: n, message: "column alignment — one space before operators; padding decays and hides diffs")
          end
        end

        RuleDSL.rule :STRICT_MODE_ZSH,
          severity: :error, tags: %i[ROBUSTNESS], applies_to: %i[zsh bash sh],
          description: "set -euo pipefail at script top" do |src, path:|
          next [] unless path.to_s.end_with?(".zsh", ".sh")
          next [] if src.match?(/^\s*set\s+-[eE]/m)

          [finding(line: 1, message: "missing set -euo pipefail after shebang")]
        end

      end
    end
  end
end
