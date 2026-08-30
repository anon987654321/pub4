# frozen_string_literal: true

# The failing-gate half of the work queue, measured rather than typed.
#
# Every entry comes from a gate that is failing right now and carries the
# command that reproduces it, so this half of the queue cannot claim work that
# is done or miss work nobody wrote down.
#
#   ruby MASTER/tools/todo.rb            # print
#
# It prints. TODO.md at the repo root is the one work queue and stays hand-
# maintained, because gates are half of it: an absent feature and a blocked
# dependency fail no gate. Keeping a generated file beside a hand-maintained one
# gives the repo two answers to the same question, so paste what is useful into
# TODO.md and leave the rest here.
#
# Only fast, deterministic gates run here. The constitutional scan takes 45
# minutes and needs a model for half its rules; its ceilings live in
# RAILS/gates/data/constitutional_budget.yml and it is named as a slow check
# rather than run.

require "open3"

module Pub4
  module Todo
    ROOT = File.expand_path("../..", __dir__)

    # Each: a label, the directory it runs in, and the command. A gate that
    # exits non-zero is work; its own output says what and why, so nothing here
    # restates the reason and drifts from it.
    CHECKS = [
      ["MASTER ratchets", "MASTER", %w[bundle exec ruby -Itest test/test_ratchets.rb]],
      ["MASTER spine", "MASTER", %w[bundle exec rake lint:spine]],
      ["MASTER rule reach", "MASTER", %w[bundle exec rake lint:rule_reach]],
      ["MASTER reader singularity", "MASTER", %w[bundle exec ruby -Itest test/test_reader_singularity.rb]],
      ["MASTER doc paths", "MASTER", %w[bundle exec ruby -Itest test/test_doc_paths.rb]],
      ["MASTER self-test", "MASTER", %w[bundle exec rake selftest]],
      ["RAILS css coverage", ".", %w[ruby RAILS/test/css_coverage_lint_test.rb]],
      ["RAILS chrome i18n", ".", %w[ruby RAILS/test/chrome_i18n_lint_test.rb]],
      ["RAILS css constitution", ".", %w[ruby RAILS/gates/runner.rb css_constitution]],
      ["RAILS stimulus wiring", ".", %w[ruby RAILS/gates/runner.rb stimulus_wiring]],
      ["OPENBSD checks", ".", %w[ruby OPENBSD/bin/check-openbsd]],
    ].freeze

    SLOW = [
      ["RAILS constitutional scan", "ruby RAILS/gates/runner.rb constitutional_scan",
       "~45 min; ceilings in RAILS/gates/data/constitutional_budget.yml"],
      ["MASTER constitution", "cd MASTER && bundle exec rake constitution",
       "~8 min; budget MASTER_CONSTITUTION_MAX_ACTIONABLE, default 1500"],
      ["Full gate chain", "cd MASTER && MASTER_GATE_SCAN_ONLY=1 ruby bin/gate",
       "~50 min; attaches a model, so the semantic rules run"],
    ].freeze

    module_function

    def run_check(dir, command)
      out, status = Open3.capture2e(*command, chdir: File.join(ROOT, dir))
      [status.success?, out]
    rescue StandardError => e
      [false, "#{e.class}: #{e.message}"]
    end

    # The lines worth reading from a failing gate: what it measured and what it
    # wants. A whole test-runner transcript is not a task.
    def evidence(out)
      out.lines.map(&:rstrip).reject(&:empty?)
         .select { |line| line.match?(/ceiling|exceeds|Expected|violation|findings|FAILED|—/) }
         .reject { |line| line.match?(/^\s*(#|Run options|Finished|Loaded)/) }
         .last(4)
    end

    def failures
      CHECKS.filter_map do |label, dir, command|
        ok, out = run_check(dir, command)
        next if ok

        { label:, command: command.join(" "), dir:, evidence: evidence(out) }
      end
    end

    def render(found)
      lines = ["# Failing gates", "",
               "Measured by `ruby MASTER/tools/todo.rb`. Every entry is a gate that fails right",
               "now. The repo's work queue is TODO.md at the root; this is its measured half.", ""]
      lines << (found.empty? ? "Every fast gate passes." : "## Failing gates (#{found.size})")
      lines << ""
      found.each do |item|
        lines << "### #{item[:label]}"
        lines << ""
        lines << "```zsh"
        lines << (item[:dir] == "." ? item[:command] : "cd #{item[:dir]} && #{item[:command]}")
        lines << "```"
        lines << ""
        item[:evidence].each { |line| lines << "- #{line.strip}" }
        lines << ""
      end
      lines << "## Slow checks, run deliberately"
      lines << ""
      SLOW.each { |label, command, note| lines << "- **#{label}** — `#{command}` (#{note})" }
      lines << ""
      lines.join("\n")
    end

    def call
      puts render(failures)
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit(Pub4::Todo.call)
end
