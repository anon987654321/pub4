# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# The rule asks CommitGuard which symbols a file has lost since recent commits
# and turns each answer into a finding. Its own logic is the two guard clauses,
# that mapping, and a rescue — so the guard is injected and all four are
# asserted, rather than running against whatever this repository's history
# happens to contain today.
#
# A history-backed test would be the stronger one and it is not free: CommitGuard
# needs real commits, so it wants a temporary repository fixture. What is here
# is everything that can be pinned without one, which is everything the rule
# itself decides.
class TestAstOmissionRule < Minitest::Test
  Rules = Master::Review::Scan::Rules
  ROOT = "/repo"

  Omission = Struct.new(:type, :name, :last_seen_at)

  # Answers CommitGuard's one call. `paths` is captured so a test can assert the
  # rule asked about the file it was given, and refute that it asked at all.
  class FakeGuard
    attr_reader :asked

    def initialize(omissions: [], raises: nil)
      @omissions = omissions
      @raises = raises
      @asked = []
    end

    def check(paths:)
      @asked << paths
      raise @raises if @raises

      @omissions
    end
  end

  def rule_with(guard)
    rule = Rules::AstOmissionRule.new(root: ROOT)
    rule.instance_variable_set(:@guard, guard)
    rule
  end

  def test_each_dropped_symbol_becomes_a_finding_naming_it
    guard = FakeGuard.new(omissions: [Omission.new("method", "synthesize", "2026-09-01")])
    found = rule_with(guard).check("", path: "#{ROOT}/lib/voice/speech.rb")

    assert_equal 1, found.size
    assert_includes found.first.message, "synthesize"
    assert_includes found.first.message, "method"
    assert_includes found.first.message, "2026-09-01",
                    "when it was last seen is how the reader decides whether the drop was deliberate"
  end

  def test_every_omission_is_reported_not_only_the_first
    guard = FakeGuard.new(omissions: [Omission.new("method", "one", "2026-09-01"),
                                      Omission.new("constant", "TWO", "2026-09-02")])

    assert_equal 2, rule_with(guard).check("", path: "#{ROOT}/lib/a.rb").size
  end

  def test_a_file_that_dropped_nothing_is_silent
    assert_empty rule_with(FakeGuard.new).check("", path: "#{ROOT}/lib/a.rb")
  end

  # The rule asks about the path relative to its root, because that is the name
  # git knows the file by. Asking about the absolute path finds nothing and
  # would look exactly like a clean file.
  def test_it_asks_the_guard_about_the_repository_relative_path
    guard = FakeGuard.new
    rule_with(guard).check("", path: "#{ROOT}/lib/voice/speech.rb")

    assert_equal [["lib/voice/speech.rb"]], guard.asked
  end

  # A guard clause that returns empty and one that never runs are the same from
  # outside, so this asserts the guard was not consulted at all.
  def test_a_non_ruby_path_is_skipped_without_consulting_git
    guard = FakeGuard.new(omissions: [Omission.new("method", "gone", "2026-09-01")])

    assert_empty rule_with(guard).check("", path: "#{ROOT}/lib/voice/speech.scss")
    assert_empty guard.asked, "a non-Ruby file must not cost a git call"
  end

  # Degrading rather than raising is deliberate: a scan that dies on one
  # unreadable file reports every remaining file as unexamined. The swallow is
  # logged in the rule.
  def test_a_failing_guard_degrades_to_no_findings_rather_than_raising
    guard = FakeGuard.new(raises: RuntimeError.new("git is unhappy"))

    assert_empty rule_with(guard).check("", path: "#{ROOT}/lib/a.rb")
  end

  # rule_deps orders by this string and the registry keys on it, so a rename
  # that misses either is a rule that quietly leaves the graph.
  def test_it_registers_under_the_id_the_dependency_graph_names
    assert_equal "ast_omission", Rules::AstOmissionRule.new(root: ROOT).id.to_s
  end
end
