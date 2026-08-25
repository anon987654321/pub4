# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

class NoLibBackedgesTest < Minitest::Test
  # Scoped to the class: three files in one test process defined a top-level
  # ROOT, one of them a String, and load order picked the winner.
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  LIB = ROOT.join("lib")
  # The fold spine moved from core/ into lib/core/ on 2026-08-12. The directory
  # boundary that used to make this test trivially true is gone, so the test now
  # does the work that boundary was doing: name the fold's files explicitly and
  # prove none of them reaches for the application spine around it.
  CORE = [LIB.join("core.rb"), *LIB.join("core").glob("**/*.rb")].freeze

  def test_core_files_do_not_require_lib
    offenders = []
    CORE.each do |path|
      text = path.read
      next unless text.match?(/\b(require|require_relative)\b/)

      text.each_line.with_index(1) do |line, lineno|
        next unless line.match?(/^\s*(require|require_relative)\s+["']/)
        # Its own namespace and the stdlib are fine; a sibling under lib/ is not.
        next if line.match?(/["'](open3|yaml|json|ruby_llm|tmpdir|fileutils|timeout|securerandom|rbconfig|pathname|shellwords|set|time|digest|open-uri|uri|net\/http|etc|io\/console)["']/)

        offenders << "#{path.relative_path_from(ROOT)}:#{lineno}: #{line.strip}"
      end
    end

    assert_empty offenders, "lib/core (the fold spine) must not require the rest of lib/:\n#{offenders.join("\n")}"
  end

  def test_the_fold_spine_is_actually_being_looked_at
    refute_empty CORE, "no fold-spine files found — this test would pass having measured nothing"
    assert_includes CORE.map { |p| p.basename.to_s }, "fold.rb"
  end
end
