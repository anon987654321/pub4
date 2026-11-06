# frozen_string_literal: true

require "stringio"
require "tmpdir"
# test_helper first: bundler/setup must pin the bundle's date before yaml's
# psych can activate the default-gem date, later in, and split the bundle.
require_relative "test_helper"
require "yaml"
require_relative "../tools/backlog"

# The backlog is the one machine-readable view of TODO.md's checkbox items:
# this file holds the generator to the source the way the tools hold the
# tools to theirs — one row per unchecked item, stable ids, a done-where a
# command is named, and a check that fails the day the pair drifts.
class TestBacklog < Minitest::Test
  # A span that reads as a runnable command, and the prose verb that makes it
  # one: spans are read backtick-pair by backtick-pair, exactly the way the
  # prose is written, so prose sitting between two code spans is never
  # mistaken for one. Restated apart from the tool so a broken extraction
  # cannot grade itself green.
  COMMAND_SPAN = %r{\b(?:bundle exec|rake \w|\bruby \b|\bnode \b|pfctl|cd [A-Z]|(?:MASTER|OPENBSD)/bin/\w)}
  PROSE_RUN = /
    \b(?:run(?:s|ning)?|ran|re-?run|execut(?:e|es|ed)|verif(?:y|ies|ied)|
    validat(?:e|es|ed)|measur\w*|audit\w*|refresh\w*|captur\w*)\b
  /xi

  def entries
    @rows ||= Backlog.generate
  end

  def silent = StringIO.new

  def named_command?(text)
    text.scan(/`([^`\n]+)`/).flatten.any? { |span| span.match?(COMMAND_SPAN) }
  end

  def test_one_entry_per_unchecked_checkbox
    pub5 = false
    nonpub5 = 0
    File.foreach(Backlog::SOURCE) do |line|
      pub5 = true if line.start_with?("## pub5")
      nonpub5 += 1 if !pub5 && line.match?(/\A- \[ \]/)
    end

    assert_equal nonpub5 + 1, entries.size
  end

  def test_ids_are_stable_across_reads_and_unique
    first = entries.map { |row| row[:id] }
    second = entries.map { |row| row[:id] }

    assert_equal first, second
    assert_equal first.size, first.uniq.size
  end

  def test_text_and_section_are_present_on_every_row
    entries.each do |row|
      assert_kind_of String, row[:id]
      refute_empty row[:text]
      refute_empty row[:section]
      assert_kind_of Array, row[:scope_paths]
    end
  end

  def test_tree_kind_and_size_stay_in_the_registered_vocabularies
    entries.each do |row|
      assert_includes Backlog::TREES, row[:tree]
      assert_includes Backlog::KINDS, row[:kind]
      assert_includes Backlog::SIZES, row[:size]
    end
  end

  def test_done_when_and_its_reason_never_both_speak
    entries.each do |row|
      if row[:done_when]
        assert_nil row[:done_when_note]
        refute_empty row[:done_when]
      else
        refute_empty row[:done_when_note], "row #{row[:id]} names no done_when and no reason"
      end
    end
  end

  def test_the_operator_seam_rows_are_operator_only
    seams = entries.select { |row| row[:section].include?("8.5 Operator-only") }

    refute_empty seams, "the consolidated register carries one operator-seam section"
    assert(seams.all? { |row| row[:kind] == "operator-only" })
    assert(seams.all? { |row| row[:tree] == "operator" })
  end

  def test_no_other_row_claims_the_operator_tree
    assert_equal claimed_by_rule, claimed_by_tree
  end

  def test_done_when_covers_every_row_that_names_a_runnable_command
    entries.each do |row|
      next unless named_command?(row[:text]) && row[:text].match?(PROSE_RUN)

      refute_nil row[:done_when],
        "row #{row[:id]} names a runnable command but carries no done_when"
    end
  end

  def test_done_when_is_verbatim_from_the_baymard_gates_row
    gates = entries.find { |row| row[:text].include?("ux:baymard") }

    refute_nil gates
    assert_equal "rake lint:law_parity", gates[:done_when]
  end

  def test_the_pinned_ruby_verification_row_names_its_command
    pinned = entries.find { |row| row[:text].include?("MASTER on pinned Ruby 4.0.5") }

    refute_nil pinned
    assert_equal "rake test", pinned[:done_when].split(" ").last(2).join(" ")
  end

  def test_the_2026_11_04_intake_items_left_the_register
    generated = entries.find { |row| row[:text].include?("generated from this file") }
    done_when = entries.find { |row| row[:text].include?("machine-checkable \"done when\"") }

    assert_nil generated, "the backlog generator landed; its intake rows are not work anymore"
    assert_nil done_when, "the done-when intake landed with the generator"
  end

  def test_pub5_is_one_plan_entry_gated_on_the_freeze_condition
    plans = entries.select { |row| row[:kind] == "plan" }

    assert_equal 1, plans.size
    assert_equal "cross", plans.first[:tree]
    assert_nil plans.first[:done_when]
    assert(plans.first[:done_when_note].include?("freeze"))
  end

  def test_scope_paths_follow_the_paths_the_text_names
    gates = entries.find { |row| row[:text].include?("ux:baymard") }

    refute_nil gates, "the row that names MASTER/Rakefile must claim it as scope"
    assert(gates[:scope_paths].include?("MASTER/Rakefile"))
    refute(entries.any? { |row| row[:scope_paths].any? { |path| path.end_with?("/") } })
  end

  def test_sizes_grow_monotonically_with_text_length
    order = { "s" => 0, "m" => 1, "l" => 2 }
    ranks = entries.sort_by { |row| row[:text].length }.map { |row| order[row[:size]] }

    assert_equal ranks, ranks.sort
  end

  def test_check_passes_on_a_clean_checkout
    state = Dir.chdir(Backlog::MASTER_ROOT) do
      `git status --porcelain -- ../TODO.md data/backlog.yml`.strip
    end
    skip "TODO.md or data/backlog.yml is dirty in this checkout" unless state.empty?

    assert_equal 0, Backlog::Store.check(io: silent)
  end

  def test_check_flags_a_source_that_grew
    Dir.mktmpdir("backlog-check") do |dir|
      out = File.join(dir, "backlog.yml")
      assert_equal 0, Backlog::Store.write(out:, io: silent)

      drifted = File.join(dir, "todo.md")
      lines = File.readlines(Backlog::SOURCE)
      # The item enters above the pub5 plan, which folds its own rows away:
      # an item appended after it would change nothing and prove nothing.
      pub5_at = lines.rindex { |line| line.start_with?("## pub5") }
      lines.insert(pub5_at, "- [ ] An item the source never carried.\n")
      File.write(drifted, lines.join)

      assert_equal 1, Backlog::Store.check(source: drifted, out:, io: silent)
    end
  end

  def test_write_refuses_a_row_whose_id_carries_changed_text
    Dir.mktmpdir("backlog-guard") do |dir|
      out = curate_first_row(dir)

      # The ids are derived from the text, so an id whose text moved is a hand
      # curation or a collision; either way the write stops.
      assert_equal 1, Backlog::Store.write(out:, io: silent)
    end
  end

  def test_write_refresh_replaces_the_curated_text
    Dir.mktmpdir("backlog-guard") do |dir|
      out = curate_first_row(dir)
      edited = YAML.load_file(out)["entries"].first["text"]

      assert_equal 0, Backlog::Store.write(out:, refresh: true, io: silent)
      refute_equal edited, YAML.load_file(out)["entries"].first["text"]
    end
  end

  def test_the_check_flags_a_hand_curated_field
    Dir.mktmpdir("backlog-curate") do |dir|
      out = File.join(dir, "backlog.yml")
      assert_equal 0, Backlog::Store.write(out:, io: silent)

      data = YAML.load_file(out)
      data["entries"].first["kind"] = "product"
      File.write(out, YAML.dump(data))

      assert_equal 1, Backlog::Store.check(out:, io: silent)
    end
  end

  private

  # The consolidated register marks one section (8.5) as operator seams by
  # heading; the classification honors that mark, restated here so a widened
  # OPERATOR_ONLY rule shows up as a tree-count mismatch.
  def claimed_by_rule
    entries.select { |row| row[:section].include?("8.5 Operator-only") }
           .map { |row| row[:id] }.uniq.sort
  end

  def claimed_by_tree
    entries.select { |row| row[:tree] == "operator" }.map { |row| row[:id] }.sort
  end

  def curate_first_row(dir)
    out = File.join(dir, "backlog.yml")
    assert_equal 0, Backlog::Store.write(out:, io: silent)

    data = YAML.load_file(out)
    data["entries"].first["text"] = "A deliberately edited row that TODO.md does not carry."
    File.write(out, YAML.dump(data))
    out
  end
end
