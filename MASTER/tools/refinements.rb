# frozen_string_literal: true

# The refinement inventory: every small, local, mechanical change the scanner
# can already see, grouped so a session can take one group and finish it.
#
# This exists because a list of refinements written by hand goes stale the day
# it is written, and because the alternative — inventing plausible-sounding
# improvements — produces work nobody measured. Every line below comes out of
# the same scanner the gate runs.
#
#   ruby MASTER/tools/refinements.rb            # the groups, largest first
#   ruby MASTER/tools/refinements.rb --items    # every refinement, one per line
#   ruby MASTER/tools/refinements.rb --tree RAILS
#   ruby MASTER/tools/refinements.rb --rule FROZEN_STRING_LITERAL
#
# A group is a batch: one rule, one kind of edit, a known file list. Closing one
# is a session with a single subject, which is the shape this repo finishes.

require "English"
require "json"
require_relative "../lib/master"

module Operator
  module Refinements
    MASTER_DIR = File.expand_path("..", __dir__)
    ROOT = File.expand_path("..", MASTER_DIR)

    # The scanner's own vocabulary. rules.yml declares the patterns, patterns.yml
    # carries the corpus behind them, and the false-positive fixture is a file of
    # deliberate violations a test asserts are NOT flagged. Scanning them reads
    # the dictionary as prose: 478 findings in rules.yml alone, none of them a
    # defect in anything.
    SELF_DESCRIBING = [
      "MASTER/data/rules.yml",
      "MASTER/data/patterns.yml",
      "MASTER/test/test_scan_rule_false_positives.rb",
    ].freeze

    # What closing one of these looks like. A group with no entry here still
    # prints, without a sentence.
    CLOSING = {
      "FROZEN_STRING_LITERAL" => "add the magic comment to the top of each file",
      "TRAILING_COMMAS" => "add the comma to the last element of each multi-line literal",
      "TAB_CHARACTER" => "convert the tabs to spaces, whole file at a time",
      "DOLLAR_PAREN" => "replace backticks with $( ) in the shell scripts",
      "DOUBLE_BRACKET" => "replace [ ] with [[ ]] — but read the shebang first, " \
                          "because a file that declares itself POSIX sh is right as it stands",
      "STRICT_MODE_ZSH" => "add set -e and the pipefail equivalent at the top of each script",
      "NO_PUTS" => "route the output through the logger or the dmesg tag the file already uses",
      "NO_DEBUG" => "delete the call that halts execution for inspection",
      "LONG_LINE" => "break the line at its natural clause, one decision per line",
      "TRAILING_COMMENT" => "move the comment above the line it explains",
      "NO_COLUMN_ALIGN" => "collapse the aligned columns to single spaces",
      "NO_ASCII_LINE_ART" => "delete the box drawing, keep the words",
      "RAILS_TAG_HELPER" => "replace the raw HTML string with tag or content_tag",
      "PREFER_TAG_HELPERS" => "same edit as RAILS_TAG_HELPER, in the view layer",
      "NO_LOGIC_IN_VIEW" => "move the condition into a helper or the presenter",
      "magic_number" => "name the number as a constant where it is used more than once",
      "NO_ABBREVIATED_IDENTIFIERS" => "spell the identifier out",
      "SMALL_FUNCTIONS" => "extract the middle of the method and name it",
      "SMALL_FILES" => "the file is under the floor — fold it into its one caller, or leave it and record why",
      "LAZY_CLASS" => "the class carries one method — fold it into its caller",
      "FEW_ARGUMENTS" => "group the arguments that travel together into one object",
      "LONG_PARAMETER_LIST" => "same edit as FEW_ARGUMENTS",
      "FEATURE_ENVY" => "move the method to the object whose data it reads",
      "LAW_OF_DEMETER" => "ask the neighbour, not the neighbour's neighbour",
      "COUPLER_SMELLS" => "give the pair of objects one seam instead of two",
      "duplicate_code" => "name the shared shape once and call it twice",
      "SILENT_RESCUE" => "log the swallow or let it raise — Ground::Swallow.log is the house form",
      "FAIL_VISIBLY" => "report the failure where a person reads it, not into a return value",
      "NEVER_BATCH_DELETE" => "delete one named thing, or ask",
      "NO_VAR" => "use let or const",
      "NO_GOD_CLASS" => "the class has outgrown one subject — split it along the seam it already has",
      "RATE_LIMITING_MISSING" => "add rate_limit to the sensitive action",
      "MIGRATION_ADD_REFERENCE_NO_FK" => "add foreign_key: true",
      "TYPOGRAPHY_DISCIPLINE" => "use the type scale token instead of the literal size",
      "CONFIG_HIERARCHY" => "move the key to the layer that owns it",
      "FILE_SPRAWL" => "the directory is past its file budget — group or fold",
      "PATH_PURPOSE" => "the path does not say what the file is for — rename or move it",
      "SIMULATION" => "do the thing or say you did not — never mime it",
      "COMPLETION_THEATER" => "implement it or delete it, never a placeholder",
      "ABC_SIZE" => "the method decides too much — split at the branch",
      "PATTERN_EXTRACTION" => "the shape repeats — give it a name",
      "NULL_BLINDNESS" => "use .nil? in Ruby and IS NULL in SQL",
      "STALE_NAMESPACE" => "use the replacement in data/rules.yml#stale_namespaces",
      "CONTROL_CHARS" => "delete the control character",
      "SQL_INJECTION" => "parameterize the query",
      "veto_patterns" => "a veto is not a refinement — read it before touching the file",
    }.freeze

    class << self
      def run(argv)
        options = parse(argv)
        rows = findings
        rows = rows.select { |r| r[:tree] == options[:tree] } if options[:tree]
        rows = rows.select { |r| r[:rule] == options[:rule] } if options[:rule]

        options[:items] ? print_items(rows) : print_groups(rows)
      end

      def parse(argv)
        options = { items: false, tree: nil, rule: nil }
        argv.each_with_index do |arg, index|
          options[:items] = true if arg == "--items"
          options[:tree] = argv[index + 1] if arg == "--tree"
          options[:rule] = argv[index + 1] if arg == "--rule"
        end
        options
      end

      def print_groups(rows)
        groups = rows.group_by { |row| row[:rule] }.sort_by { |_, members| -members.size }
        puts "refinements: #{rows.size} in #{rows.map { |r| r[:file] }.uniq.size} files, #{groups.size} groups"
        puts
        groups.each do |rule, members|
          trees = members.group_by { |row| row[:tree] }
                         .sort_by { |_, rows_in_tree| -rows_in_tree.size }
                         .map { |tree, rows_in_tree| "#{tree} #{rows_in_tree.size}" }
                         .join(", ")
          puts format("%-32s %5d in %4d files", rule, members.size, members.map { |m| m[:file] }.uniq.size)
          puts "    #{trees}"
          puts "    #{CLOSING.fetch(rule, "no closing sentence written yet")}"
        end
      end

      def print_items(rows)
        rows.sort_by { |row| [row[:file], row[:line].to_i] }.each do |row|
          puts format("%s:%s  %s — %s", row[:file], row[:line], row[:rule], row[:message])
        end
        puts "# #{rows.size} refinements"
      end

      def findings
        corpus = tracked.reject { |rel| SELF_DESCRIBING.include?(rel) }
                        .map { |rel| File.join(ROOT, rel) }
                        .select { |abs| File.file?(abs) }
                        .reject { |abs| Master::Review::Scan::Scanner.skip_path?(abs, root: ROOT) }

        scanner = Master::Review::Scan::InfraHelpers.build_scanner(root: MASTER_DIR)
        scanner.findings(corpus, depth: :deep).map do |hit|
          relative = hit[:path].to_s.delete_prefix("#{ROOT}/")
          {
            tree: relative.split("/").first,
            file: relative,
            line: hit[:line],
            rule: hit[:rule].to_s,
            severity: hit[:severity].to_s,
            message: hit[:message].to_s[0, 160],
          }
        end
      end

      def tracked
        listed = IO.popen(["git", "-C", ROOT, "ls-files"], &:read).split("\n")
        raise "refinements: git ls-files failed in #{ROOT}" unless $CHILD_STATUS.success?

        listed
      end
    end
  end
end

Operator::Refinements.run(ARGV) if $PROGRAM_NAME == __FILE__
