# frozen_string_literal: true

# runner.rb's two read-only answers, --list and --explain. Neither runs a check,
# so neither belongs beside the code that does. Both read the runner's own
# CHECKS, subprocess?, needs and SUBPROCESS_INCONCLUSIVE, which are defined
# before runner.rb requires this file.

def list_checks
  puts "Available checks (use the short name with runner.rb):"
  CHECKS.each do |name, row|
    kind = subprocess?(row) ? "subprocess #{row['script']}" : row["class"]
    puts "  #{name.ljust(22)} #{kind}"
  end

  puts
  puts "Composite checks (their leaves are skipped when the parent is also selected):"
  CHECKS.group_by { |_, row| row["covered_by"] }.each do |parent, rows|
    next unless parent

    puts "  #{parent} includes: #{rows.map(&:first).join(', ')}"
  end
end

# The switches that change a verdict without appearing on the command line. Each
# is read somewhere deep in a check, so a run that behaves differently on the
# deploy host than on a laptop is usually one of these, and nothing else lists
# them together.
ENV_SWITCHES = {
  "CHECK_STRICT_INCONCLUSIVE" => "a check that measured nothing fails instead of reading inconclusive",
  "CHECK_STRICT_SOFT" => "soft findings (contrast pairs, surface schema) fail instead of warning",
  "CHECK_AUDITOR_STRICT" => "frontend_auditor fails on warnings; without it only auditor errors block " \
                           "and warnings are reported, so the warning half is advisory",
  "CHECK_AUTOFIX" => "0 makes fixing checks report-only; unset they fix and remeasure",
  "CHECK_SKIP_NESTED" => "production skips the leaves it would otherwise run itself",
  "VISUAL_CAPTURE" => "1 lets visual_contract capture pixels (VISUAL_CAPTURE_APP, VISUAL_CAPTURE_BASE); " \
                      "without it the check compares nothing and exits inconclusive",
  "CHECK_PIXEL_BASELINE_STRICT" => "missing or unsupported PNG baselines fail browser_diagnostics",
  "CHECK_PIXEL_DIFF_MAX_RATIO" => "maximum changed-pixel ratio per viewport; finite from 0 to 1, default 0.01",
  "CHECKS_FILE" => "reads a different check registry in place of checks.yml",
}.freeze

# What --all would do, without doing it: every check in run order, what it runs,
# what it needs, which composite already covers it and the line it prints when
# it passes. Pass lines are shown as declared, placeholders unresolved, so
# explaining never walks the inventory.
def explain_checks
  puts "Checks in run order (#{CHECKS.size}):"

  CHECKS.each do |name, row|
    kind = subprocess?(row) ? "subprocess #{row['script']}" : row["class"]
    notes = []
    notes << "needs #{needs(name).join(', ')}" if needs(name).any?

    notes << "covered by #{row['covered_by']}" if row["covered_by"]
    row.fetch("env_flags", {}).each { |var, keyword| notes << "#{var}=1 -> #{keyword}" }
    puts "  #{name.ljust(22)} #{kind}#{notes.empty? ? '' : " (#{notes.join('; ')})"}"
    pass = row["pass"] || "exit 0 passes, exit #{SUBPROCESS_INCONCLUSIVE} is inconclusive"
    puts "  #{' ' * 22} pass: #{pass}"
  end

  puts
  puts "Environment switches:"
  ENV_SWITCHES.each { |var, meaning| puts "  #{var.ljust(24)} #{meaning}" }
end
