# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

ROOT = Pathname.new(__dir__).join("..", "..").expand_path
LIB = ROOT.join("lib")
# The fold spine moved from core/ into lib/core/ on 2026-08-12. The directory
# boundary that used to make this test trivially true is gone, so the test now
# does the work that boundary was doing: name the fold's files explicitly and
# prove none of them reaches for the application spine around it.
CORE = [LIB.join("core.rb"), *LIB.join("core").glob("**/*.rb")].freeze

class NoLibBackedgesTest < Minitest::Test
  def test_core_files_do_not_require_lib
    offenders = []
    CORE.each do |path|
      text = path.read
      next unless text.match?(/\b(require|require_relative)\b/)

      text.each_line.with_index(1) do |line, lineno|
        next unless line.match?(/^\s*(require|require_relative)\s+["']/)
        # Its own namespace and the stdlib are fine; a sibling under lib/ is not.
        next if line.match?(/["'](open3|yaml|json|ruby_llm|tmpdir|fileutils|timeout|securerandom|rbconfig|pathname|shellwords|set|time|digest|open-uri|uri|net\/http|etc|io\/console)["']/)
        # A sibling already inside the fold is not the application spine. The
        # rule is "none of them reaches for the spine around it", and until
        # constitution.rb was split there was no fold file requiring another, so
        # a bare non-stdlib require was a safe proxy for a backedge. It is not
        # one any more: this flagged the split as a violation of a rule it does
        # not break.
        next if fold_sibling?(path, line)

        offenders << "#{path.relative_path_from(ROOT)}:#{lineno}: #{line.strip}"
      end
    end

    assert_empty offenders, "lib/core (the fold spine) must not require the rest of lib/:\n#{offenders.join("\n")}"
  end

  # Only require_relative can name a sibling, and it resolves against the
  # requiring file's directory. Membership of CORE is what decides, so a file
  # outside the fold cannot be reached this way even if it sits beside one.
  def fold_sibling?(path, line)
    target = line[/require_relative\s+["']([^"']+)["']/, 1]
    return false unless target

    CORE.include?(path.dirname.join("#{target}.rb").expand_path)
  end

  def test_the_fold_spine_is_actually_being_looked_at
    refute_empty CORE, "no fold-spine files found — this test would pass having measured nothing"
    assert_includes CORE.map { |p| p.basename.to_s }, "fold.rb"
  end
end
