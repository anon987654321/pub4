# frozen_string_literal: true

require "minitest/autorun"
require_relative "../tools/ratchets"

# Wish-list items 1 and 2, made executable.
#
# Ten instruments carried a ratchet and each had its own invocation, so the only
# way to know whether any was stale was to run all ten. On 2026-08-11 four were,
# and each was found by accident while doing something else.
#
# And "stale" had no owner. chrome_i18n_lint tested that its baselines had not been
# beaten-and-left; nothing else did, so two of that day's red tests were ceilings
# above the real number — slack the next change grows into without failing anything.
# This makes both directions the contract for every ratchet at once.
class TestRatchets < Minitest::Test
  def rows = @rows ||= Pub4::Ratchets.all

  def readable = rows.reject { |row| row.current.nil? || row.ceiling.nil? }

  def test_no_ratchet_is_over_its_ceiling
    over = readable.select(&:over?)

    assert_empty over.map { |row| "#{row.name} #{row.current}/#{row.ceiling}" },
                 "new debt against a recorded ceiling"
  end

  # The half that had one owner and now has all of them.
  def test_no_ratchet_is_slack
    slack = readable.select(&:slack?)

    assert_empty slack.map { |row| "#{row.name} #{row.current}/#{row.ceiling} — lower it in #{row.source}" },
                 "a ceiling above the real number is room the next change grows into silently"
  end

  # A tool that reports nothing is not a passing tool. This is the guard against
  # the whole file quietly going blind — the failure mode it exists to catch in
  # everything else.
  def test_it_reads_something
    assert_operator readable.size, :>=, 8,
                    "measure reads fewer ratchets than the tree has; a lint was renamed or moved " \
                    "and RAILS_LINTS did not follow"
  end

  # Each row must say where its number lives, or a failure is unactionable.
  def test_every_row_names_its_source
    assert_empty rows.reject { |row| row.source.to_s.match?(/\w/) }.map(&:name)
  end

  # The two spine numbers are not the same kind of thing and must not be reported
  # as if they were: one is a budget, one is an invariant (DECISIONS.md, 2026-08-11).
  def test_the_spine_invariant_is_marked_as_one
    core = rows.find { |row| row.name == "spine.core_files" }

    refute_nil core
    assert_equal :fixed, core.direction
  end
end
