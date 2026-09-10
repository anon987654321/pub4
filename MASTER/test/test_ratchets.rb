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
  # Every ratchet over the whole 2871-file corpus. That is a minute of real
  # measurement, not a hang, and the default 30s bound exists to catch hangs.
  def test_timeout = 300

  def rows = @rows ||= Pub4::Ratchets.all

  def readable = rows.reject { |row| row.current.nil? || row.ceiling.nil? }

  def test_no_ratchet_is_over_its_ceiling
    over = readable.select(&:over?)

    assert_empty over.map { |row| "#{row.name} #{row.current}/#{row.ceiling}" },
                 "new debt against a recorded ceiling"
  end

  # The half that had one owner and now has all of them.
  #
  # Skipped when the measured trees are dirty, and that is not a loophole. This
  # assertion's advice is "lower the recorded number", which writes a permanent
  # value from a transient measurement — and this repo's working tree is shared
  # by several sessions at once, routinely carrying 30-80 uncommitted files.
  #
  # Measured 2026-08-15: MASTER/lib came to 39,251 code lines in the shared tree
  # and 39,379 on a clean checkout of the same commit, because another session
  # was midway through deleting about 128 lines. The ceiling is 39,258. So the
  # shared tree said "slack, lower it to 39,251" while the committed truth was
  # 121 lines OVER. Following the advice would have recorded a number nobody's
  # checkout agrees with and hidden real growth behind it.
  #
  # Over-ceiling stays a hard failure in either state: over-reporting something
  # to fix is safe, and recording a wrong number is not.
  def test_no_ratchet_is_slack
    if (dirty = uncommitted_measured_paths).any?
      skip "measured trees are dirty (#{dirty.size} file(s), e.g. #{dirty.first}) — " \
           "slack advice writes a permanent number from a transient measurement; " \
           "re-run in a clean checkout"
    end

    slack = readable.select(&:slack?)

    assert_empty slack.map { |row| "#{row.name} #{row.current}/#{row.ceiling} — lower it in #{row.source}" },
                 "a ceiling above the real number is room the next change grows into silently"
  end

  # Shelling out is fine here and deliberately not in tools/ratchets.rb, whose
  # header promises that fast mode only reads files.
  def uncommitted_measured_paths
    root = Pub4::Ratchets::ROOT
    out = `cd #{root.inspect} && git status --porcelain -- MASTER/lib MASTER/data RAILS 2>/dev/null`
    out.to_s.lines.map { |line| line[3..].to_s.strip }.reject(&:empty?)
  rescue StandardError # scan: intentional — unparseable status becomes unreadable rows, which the assertion reports
    []
  end

  # A tool that reports nothing is not a passing tool. This is the guard against
  # the whole file quietly going blind — the failure mode it exists to catch in
  # everything else.
  def test_it_reads_something
    assert_operator readable.size, :>=, 8,
                    "measure reads fewer ratchets than the tree has; a lint was renamed or moved " \
                    "and RAILS_LINTS did not follow"
  end

  # The growth population is git's, not the working tree's. This checkout is
  # shared, and a walk of the disk charged one session for another's uncommitted
  # files: an untracked stems render raised growth.studio against a session that
  # had never opened STUDIO. Both directions, because a census that counted
  # nothing would pass the first assertion on its own.
  def test_growth_counts_tracked_files_and_not_the_working_tree
    intruder = File.join(Pub4::Ratchets::ROOT, "MASTER", "test", "untracked_growth_probe.rb")
    before = Pub4::Ratchets.tree_source_files("MASTER").size
    File.write(intruder, "# frozen_string_literal: true\n")
    forget_tracked_files

    assert_equal before, Pub4::Ratchets.tree_source_files("MASTER").size,
                 "an untracked file is somebody's work in progress, not this tree's growth"
    assert_includes Pub4::Ratchets.tracked_source_files, "MASTER/tools/ratchets.rb",
                    "a tracked source file must still be counted"
  ensure
    File.delete(intruder) if intruder && File.exist?(intruder)
    forget_tracked_files
  end

  def forget_tracked_files = Pub4::Ratchets.instance_variable_set(:@tracked_source_files, nil)

  # The whole value of --why is that the list and the number are the same
  # measurement. A row whose members do not add up to its own count is worse than
  # a row with no members: it reads as attribution and attributes wrongly.
  def test_members_agree_with_the_count_they_stand_behind
    disagreeing = rows.select { |row| row.members && row.members.size != row.current }
    assert_empty disagreeing.map { |row| "#{row.name}: #{row.members.size} members vs #{row.current}" }
  end

  # An integer nobody can decompose is the state this flag exists to end, so most
  # of the register has to be able to answer. Not all of it: file_length and
  # coverage_ratchet are pointers to a test that owns the number.
  def test_most_rows_can_name_their_members
    answerable = rows.count(&:members)
    assert_operator answerable, :>=, (rows.size * 0.7).floor,
                    "only #{answerable} of #{rows.size} rows can say what their number is made of"
  end

  def test_why_names_the_members_and_falls_back_to_an_index
    named = rows.find { |row| row.members&.any? }
    refute_nil named, "no row carries members, so --why has nothing to prove"
    assert_includes Pub4::Ratchets.why(rows, named.name), named.members.first.to_s
    assert_includes Pub4::Ratchets.why(rows, "no-such-row"), "rows can name their members"
  end

  # --since asks git, not a second census, so it has to work from a worktree and
  # on a tree whose ceilings have not moved.
  def test_since_reads_recorded_ceilings_out_of_git
    report = Pub4::Ratchets.since("HEAD", rows)

    assert_includes report, "measure --since HEAD"
    refute_includes report, "unparseable"
  end

  def test_numeric_leaves_keys_by_path
    leaves = Pub4::Ratchets.numeric_leaves({ "a" => { "b" => 3 }, "c" => "not a number", "d" => 4 })

    assert_equal({ "a.b" => 3, "d" => 4 }, leaves)
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
