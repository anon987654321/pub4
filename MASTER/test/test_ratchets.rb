# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/operator/ratchets"

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

  # Measured once per process. Each of the ten tests reading rows paid for its
  # own two-minute measurement, and the file alone ran past bin/check's 900s
  # step timeout, so check:ci reported `test` failed with no test named.
  def self.rows = @rows ||= Operator::Ratchets.all

  def rows = self.class.rows

  def readable = rows.reject { |row| row.current.nil? || row.ceiling.nil? }

  def test_no_ratchet_is_over_its_ceiling
    over = readable.select(&:over?)

    assert_empty over.map { |row| "#{row.name} #{row.current}/#{row.ceiling}" },
                 "new debt against a recorded ceiling"
  end

  def test_missing_rails_lints_are_not_silently_omitted
    notes = with_rails(Dir.mktmpdir) { Operator::Ratchets.rails_lint_rows.map(&:note) }

    assert_equal Operator::Ratchets::RAILS_LINTS.size, notes.size, "every lint keeps its row"
    assert_equal ["unreadable: lint file missing"], notes.uniq
  end

  def test_a_lint_file_without_its_module_is_unreadable
    path = File.join(Operator::Ratchets::RAILS, Operator::Ratchets::RAILS_LINTS.fetch("asset_url"))
    finder = Operator::Ratchets.method(:lint_module)
    Operator::Ratchets.define_singleton_method(:lint_module) { |_path| nil }
    row = Operator::Ratchets.rows_for_lint("asset_url", path)

    assert_nil row.current
    assert_match(/\Aunreadable: .*Operator lint module missing/, row.note)
  ensure
    Operator::Ratchets.define_singleton_method(:lint_module, finder) if finder
  end

  def test_missing_css_budget_is_not_silently_omitted
    fast, deep = with_rails(Dir.mktmpdir) do
      [Operator::Ratchets.css_budget_rows, Operator::Ratchets.css_constitution_rows]
    end

    assert_equal [["css_budget", nil, nil, "unreadable: budget missing"]],
                 fast.map { |row| [row.name, row.current, row.ceiling, row.note] }
    assert_equal [["css_budget", "unreadable: no CSS ceilings available"]],
                 deep.map { |row| [row.name, row.note] }
  end

  def with_rails(dir)
    original = Operator::Ratchets::RAILS
    Operator::Ratchets.send(:remove_const, :RAILS)
    Operator::Ratchets.const_set(:RAILS, dir)
    yield
  ensure
    Operator::Ratchets.send(:remove_const, :RAILS)
    Operator::Ratchets.const_set(:RAILS, original)
    FileUtils.remove_entry(dir) if dir != original && File.directory?(dir)
  end

  def test_no_ratchet_is_unreadable
    # Pointer rows (file_length, coverage_ratchet) and the fast css_budget rows
    # carry no number by design; their own tests or --deep measure them. A row
    # whose measurement failed says "unreadable:", as master_row and
    # unreadable_row write it.
    unreadable = rows.select { |row| row.note.to_s.start_with?("unreadable") }

    assert_empty unreadable.map { |row| "#{row.name}: #{row.note}" },
                 "an unreadable ratchet is evidence that measurement failed, not a pass"
  end

  def test_command_and_name_ratchets_are_in_the_register
    names = rows.map(&:name)

    assert_includes names, "command_surface"
    assert_includes names, "name_candidates"
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
    root = Operator::Ratchets::ROOT
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
    intruder = File.join(Operator::Ratchets::ROOT, "MASTER", "test", "untracked_growth_probe.rb")
    before = Operator::Ratchets.tree_source_files("MASTER").size
    File.write(intruder, "# frozen_string_literal: true\n")
    forget_tracked_files

    assert_equal before, Operator::Ratchets.tree_source_files("MASTER").size,
                 "an untracked file is somebody's work in progress, not this tree's growth"
    assert_includes Operator::Ratchets.tracked_source_files, "MASTER/lib/operator/ratchets.rb",
                    "a tracked source file must still be counted"
  ensure
    File.delete(intruder) if intruder && File.exist?(intruder)
    forget_tracked_files
  end

  # A growth row that counted tests taxed coverage at the rate it taxed sprawl.
  def test_growth_counts_source_and_not_tests
    master = Operator::Ratchets.pub4_growth_rows.find { |row| row.name == "growth.master" }

    assert_includes master.members, "MASTER/lib/operator/ratchets.rb", "a source file must still be counted" # source-assertion: ok — a census result, not a source file
    refute_includes master.members, "MASTER/test/test_ratchets.rb", "a test is coverage, not sprawl"
    refute_includes master.members, "MASTER/web/test/test_helper.rb", "a nested test directory is still tests"
  end

  def forget_tracked_files =Operator::Ratchets.instance_variable_set(:@tracked_source_files, nil)

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
    assert_includes Operator::Ratchets.why(rows, named.name), named.members.first.to_s
    assert_includes Operator::Ratchets.why(rows, "no-such-row"), "rows can name their members"
  end

  # --since asks git, not a second census, so it has to work from a worktree and
  # on a tree whose ceilings have not moved.
  def test_since_reads_recorded_ceilings_out_of_git
    report = Operator::Ratchets.since("HEAD", rows)

    assert_includes report, "measure --since HEAD"
    refute_includes report, "unparseable"
  end

  def test_numeric_leaves_keys_by_path
    leaves = Operator::Ratchets.numeric_leaves({ "a" => { "b" => 3 }, "c" => "not a number", "d" => 4 })

    assert_equal({ "a.b" => 3, "d" => 4 }, leaves)
  end

  # Each row must say where its number lives, or a failure is unactionable.
  def test_every_row_names_its_source
    assert_empty rows.reject { |row| row.source.to_s.match?(/\w/) }.map(&:name)
  end

  def test_render_names_the_owner_for_an_off_row
    rows = [
      Operator::Ratchets::Row.new(name: "growth.master", current: 11, ceiling: 10,
                                  direction: :down, source: "MASTER/data/spine.yml"),
      Operator::Ratchets::Row.new(name: "spine.core_files", current: 5, ceiling: 5,
                                  direction: :fixed, source: "MASTER/data/spine.yml"),
    ]

    output = Operator::Ratchets.render(rows)

    assert_match(/growth\.master .*OVER .*\(MASTER\/data\/spine\.yml\)/, output)
    refute_match(/spine\.core_files .*MASTER\/data\/spine\.yml/, output)
  end

  # The two spine numbers are not the same kind of thing and must not be reported
  # as if they were: one is a budget, one is an invariant (data/spine.yml's header).
  def test_the_spine_invariant_is_marked_as_one
    core = rows.find { |row| row.name == "spine.core_files" }

    refute_nil core
    assert_equal :fixed, core.direction
  end

  def test_the_recursive_spine_invariant_is_marked_as_one
    core = rows.find { |row| row.name == "spine.core_recursive_files" }

    refute_nil core
    assert_equal :fixed, core.direction
  end
end
