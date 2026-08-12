# frozen_string_literal: true

require_relative "test_helper"

# DEBT.md, Scanner noise: "38 of rake selfcheck's 76 findings are false positives
# from two rules: COMPLETION_THEATER matches require \"etc\", Etc.nprocessors and
# /etc/* paths; STALE_NAMESPACE flags every legitimate Master::CLI::* reference
# because \b matches before ::."
#
# Both are narrowed now — selfcheck went 71 → 34 on 2026-08-01. Narrowing a rule is
# the change most likely to quietly turn it off, so each of these asserts both
# directions: the false positive is gone AND the real violation still fires.
class TestScanRuleFalsePositives < Minitest::Test
  def scanner
    @scanner ||= Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
  end

  def rule(id)
    scanner.rules.find { |r| r.id.to_s == id.to_s } || raise("rule #{id} is not registered")
  end

  def findings(id, source, path: "lib/example.rb")
    Array(rule(id).check(source, path: File.join(Master::ROOT, path)))
  end

  # --- COMPLETION_THEATER -------------------------------------------------

  def test_completion_theater_ignores_the_etc_stdlib_and_etc_paths
    [
      %(require "etc"),
      %(cores = Etc.nprocessors),
      %(path = "/etc/rc.d/master"),
      %(sh "doas cp etc/doas.conf /etc/doas.conf"),
      %(File.read("/etc/master.env")),
    ].each do |line|
      assert_empty findings(:COMPLETION_THEATER, "#{line}\n"), "#{line.inspect} is not a placeholder"
    end
  end

  def test_completion_theater_still_catches_a_real_placeholder
    [
      %(SUPPORTED = "png, jpg, etc."),
      %(DESCRIPTION = "clusters (marketplace, playlist, etc.)"),
      %(HELP = "flags: --all, --quiet, etcetera"),
    ].each do |line|
      refute_empty findings(:COMPLETION_THEATER, "#{line}\n"), "#{line.inspect} should be flagged"
    end
  end

  def test_completion_theater_still_catches_a_trailing_ellipsis
    refute_empty findings(:COMPLETION_THEATER, "  handle_the_rest ...\n")
  end

  def test_completion_theater_skips_comments
    assert_empty findings(:COMPLETION_THEATER, "# a, b, etc.\n")
  end

  # --- STALE_NAMESPACE ----------------------------------------------------

  def stale_pairs
    config = (Master.load_yaml(Master.data_path("patterns.yml")) || {})["stale_namespaces"] || {}
    Array(config["stale_constants"]).select { |row| row.is_a?(Hash) }
  end

  def test_a_retired_constant_used_as_a_prefix_is_not_a_violation
    refute_empty stale_pairs

    stale_pairs.each do |row|
      old = row["old"]
      # Every replacement contains, or is nested under, some retired prefix — that
      # is exactly the shape that produced 25 false findings.
      assert_empty findings(:STALE_NAMESPACE, "#{row["new"]}.call\n"),
                   "#{row["new"]} is the replacement for #{old} and must not be flagged"
    end
  end

  def test_the_bare_retired_constant_is_still_a_violation
    stale_pairs.each do |row|
      refute_empty findings(:STALE_NAMESPACE, "x = #{row["old"]}\n"),
                   "#{row["old"]} is retired and must still be flagged"
    end
  end

  def test_a_longer_constant_that_merely_starts_with_a_retired_name_is_ignored
    assert_empty findings(:STALE_NAMESPACE, "Master::CLIRunner.new\n")
    assert_empty findings(:STALE_NAMESPACE, "Other::Master::Scanner.new\n")
  end

  def test_the_rules_own_file_is_exempt
    assert_empty findings(:STALE_NAMESPACE, "x = Master::CLI\n", path: "lib/review/scan/rules/naming_rules.rb")
  end

  # --- DEAD_CODE ----------------------------------------------------------
  # The detector matched a bare \b(return|raise)\b, so every guard clause read as
  # dead code. It must fire only on an unconditional terminator with reachable
  # code after it at the same or deeper indent.

  def test_dead_code_ignores_guard_clauses
    [
      "def a\n  return value if ready?\n  work\nend\n",
      "def a\n  raise Boom unless ok\n  work\nend\n",
      "def a\n  index = return_value\n  index\nend\n",
      "def a\n  cond ? return : work\n  more\nend\n",
      "def a\n  return a\nend\n\ndef b\n  work\nend\n",
    ].each do |source|
      assert_empty findings(:DEAD_CODE, source), "#{source.inspect} is not unreachable code"
    end
  end

  def test_dead_code_still_catches_a_real_unreachable_line
    refute_empty findings(:DEAD_CODE, "def a\n  return\n  work\nend\n")
  end

  # --- MAGIC_COLOR --------------------------------------------------------
  # Token definitions hold raw values; usage cites the token. A documented parody
  # opts a whole file out; one line opts out inline. It must still catch raw usage.

  def test_magic_color_ignores_definitions_and_intentional_markers
    [
      ["  --accent: #7c6fd6;\n", "app/x.scss"],
      ["  $brand: #7c6fd6;\n", "app/x.scss"],
      ["  background: #131921; // scan: intentional\n", "app/x.scss"],
      ["/* scan: intentional-colors */\n  color: #131921;\n", "app/x.scss"],
    ].each do |source, path|
      assert_empty findings(:MAGIC_COLOR, source, path: path), "#{source.inspect} is intentional or a definition"
    end
  end

  def test_magic_color_still_catches_a_raw_usage
    refute_empty findings(:MAGIC_COLOR, "  color: #7c6fd6;\n", path: "app/x.scss")
  end

  def test_magic_color_is_registered_once
    count = scanner.rules.count { |rule| rule.id.to_s == "MAGIC_COLOR" }
    assert_equal 1, count, "MAGIC_COLOR must be one rule, not #{count} (SINGULARITY: unique by id)"
  end

  # --- veto unsafe_calls --------------------------------------------------
  # Interpolation is the arbitrary-code-execution risk. The arg-array form is the
  # prescribed FIX and must not be vetoed; an interpolated shell string must be.

  def test_veto_unsafe_calls_allows_the_prescribed_arg_array_form
    [
      %(ok = system(RbConfig.ruby, script, "--input", input)\n),
      %(out, status = Open3.capture2e("git", "-C", root, "status")\n),
    ].each do |source|
      assert_empty findings(:veto_patterns, source), "#{source.inspect} is the safe arg-array form"
    end
  end

  def test_veto_unsafe_calls_still_catches_interpolated_shell_out
    refute_empty findings(:veto_patterns, %(system("rm -rf \#{directory}")\n))
  end

  # --- CONTROL_CHARS ------------------------------------------------------
  # A concurrent write left SOH bytes wrapping a string literal this session;
  # this rule catches that corruption class. Tab/newline stay legal. The SOH is
  # built with 1.chr so the test source itself carries no control character.

  def test_control_chars_ignores_clean_source_and_tabs
    ["def a\n  work\nend\n", "a\tb\n"].each do |source|
      assert_empty findings(:CONTROL_CHARS, source), "#{source.inspect} has no control characters"
    end
  end

  def test_control_chars_flags_a_stray_soh_byte
    refute_empty findings(:CONTROL_CHARS, "def a\n  x = #{1.chr}y\nend\n")
  end

  # --- DEBUG_OUTPUT -------------------------------------------------------
  # `p` is a legal variable name. The rule read `p << "…"` as a Kernel#p call
  # and flagged lib/ground/attention_context.rb twice — error severity, and
  # auto_fix=true, pointed at correct code.

  def test_debug_output_ignores_a_local_named_p
    [
      %(  p << "zoom: none"\n),
      %(  p ||= []\n),
      %(  p = compute_parts\n),
      %(  p == other\n),
    ].each do |source|
      assert_empty findings(:DEBUG_OUTPUT, source, path: "lib/example.rb"),
                   "#{source.inspect} uses a variable named p"
    end
  end

  def test_debug_output_still_catches_real_debug_calls
    [
      %(  p foo\n),
      %(  pp payload\n),
      %(  p "literal"\n),
      %(  $stderr.puts "trace"\n),
    ].each do |source|
      refute_empty findings(:DEBUG_OUTPUT, source, path: "lib/example.rb"), "#{source.inspect} is debug output"
    end
  end

  # --- the rescue family, after EMPTY_RESCUE was collapsed into it ----------
  #
  # EMPTY_RESCUE was deleted on 2026-08-12 as a pure duplicate: 37 findings across
  # MASTER, 0 unique to it, 8 double-reported at both :error and :warning. Deleting
  # a rule is the change most likely to quietly drop coverage, so this asserts the
  # thing that actually matters — every `rescue` shape it used to match is still
  # matched by one of the two survivors, and at exactly one severity.

  RESCUE_SHAPES = {
    "rescue\n" => :SILENT_RESCUE,
    "rescue StandardError\n" => :SILENT_RESCUE,
    "rescue Exception\n" => :SILENT_RESCUE,
    "rescue ArgumentError\n" => :NARROW_SILENT_RESCUE,
    "rescue Errno::ESRCH\n" => :NARROW_SILENT_RESCUE,
    "rescue Errno::ESRCH, Errno::EPERM\n" => :NARROW_SILENT_RESCUE,
  }.freeze

  def rescue_source(clause) = "def probe\n  work\n#{clause}  nil\nend\n"

  # Asked of every registered rule, not just the two survivors — a comparison
  # between SILENT_RESCUE and NARROW_SILENT_RESCUE would have passed before the
  # deletion too, since those two were already disjoint. What was broken was a
  # third rule saying the same thing, so the question has to be "how many rules in
  # this tree call this line a discard", which is exactly what it counts.
  def discard_reporters(source)
    scanner.rules.select do |rule|
      Array(rule.check(source, path: File.join(Master::ROOT, "lib/example.rb")))
        .any? { |f| f[:message].to_s.match?(/discard|swallow/i) }
    end.map { |rule| rule.id.to_s }
  end

  def test_every_rescue_shape_is_reported_by_exactly_one_rule
    RESCUE_SHAPES.each do |clause, owner|
      reporters = discard_reporters(rescue_source(clause))

      assert_equal [owner.to_s], reporters,
                   "#{clause.strip.inspect} should be one rule's finding, not #{reporters.join(' + ')}"
    end
  end

  # The comma case is the one EMPTY_RESCUE got wrong: it matched a single token, so
  # one exception class was an error and two of the same class family were a
  # warning. Both are the same code.
  def test_severity_does_not_depend_on_how_many_classes_are_listed
    one = findings(:NARROW_SILENT_RESCUE, rescue_source("rescue Errno::ESRCH\n"))
    two = findings(:NARROW_SILENT_RESCUE, rescue_source("rescue Errno::ESRCH, Errno::EPERM\n"))

    assert_equal one.size, two.size
  end

  # The predicate all of them share, and the reason the count is 35 rather than the
  # 234 a naive "rescue with no logger" search returns: a rescue that re-raises,
  # warns, logs, publishes, or returns anything other than an empty value is not a
  # discard. Every one of these is correct code that must stay unflagged.
  def test_a_rescue_that_answers_the_question_is_not_a_discard
    [
      "def probe\n  work\nrescue StandardError => e\n  raise e\nend\n",
      "def probe\n  work\nrescue StandardError => e\n  Master::Ground::Swallow.log(e)\nend\n",
      "def probe\n  work\nrescue StandardError\n  warn \"probe failed\"\nend\n",
      "def probe\n  work\nrescue StandardError\n  DEFAULT_BUDGET\nend\n",
    ].each do |source|
      %i[SILENT_RESCUE NARROW_SILENT_RESCUE].each do |id|
        assert_empty findings(id, source), "#{source.lines[2].strip.inspect} handles the error"
      end
    end
  end

  # --- the YAML lexical bridge reading comments ------------------------------
  #
  # detect_lexical is a raw regex over raw lines, so the paragraph above
  # explaining which rescue shape belongs to which rule became two error-severity
  # findings about itself — BARE_RESCUE and FAIL_VISIBLY, which share one regex.
  # Skipping comment-only lines took selfcheck from 25 to 17: those two to zero,
  # and guard_expensive_ops from 9 to 5, all four of which were prose about
  # truncation and `rm -rf`. Verified line by line that the five survivors are code.

  def bridge = scanner.rules.find { |r| r.id.to_s == "yaml_declarative" } || raise("bridge rule is not registered")

  # frozen_string_literal is a file-level `\A` rule in the same bridge and fires on
  # every fixture here, so this asks about the line rules only. Asserting the whole
  # list was empty made the test fail for a reason it was not about.
  LINE_RULES = %w[bare_rescue fail_visibly guard_expensive_ops].freeze

  def bridge_findings(source)
    Array(bridge.check(source, path: File.join(Master::ROOT, "lib/example.rb")))
      .map { |f| f[:rule].to_s }.select { |id| LINE_RULES.include?(id) }
  end

  def test_a_comment_naming_a_forbidden_construct_is_not_a_finding
    [
      "# `rescue Exception` falls to SILENT_RESCUE's non-narrow branch\n",
      "  # a bare rescue\n",
      "# Rotate rather than truncate-in-place\n",
      "  // rm -rf in a JS comment\n",
    ].each do |source|
      assert_empty bridge_findings(source), "#{source.strip.inspect} is prose, not code"
    end
  end

  def test_the_same_constructs_in_code_are_still_findings
    assert_includes bridge_findings("def probe\n  work\nrescue\n  nil\nend\n"), "bare_rescue"
    assert_includes bridge_findings("def probe\n  work\nrescue Exception\n  nil\nend\n"), "bare_rescue"
    assert_includes bridge_findings("  Item.delete_all\n"), "guard_expensive_ops"
  end

  # `@transforms << :bare_rescue` in the autofixer that repairs bare rescues was an
  # error-severity finding against itself, recorded in DEBT.md as noise rather than
  # fixed. A symbol is not a rescue clause.
  def test_a_symbol_named_bare_rescue_is_not_a_bare_rescue
    refute_includes bridge_findings("  @transforms << :bare_rescue\n"), "bare_rescue"
    refute_includes bridge_findings("  def bare_rescue\n"), "bare_rescue"
  end

  def test_the_deleted_rule_does_not_come_back
    refute scanner.rules.any? { |r| r.id.to_s == "EMPTY_RESCUE" },
           "EMPTY_RESCUE was collapsed into SILENT_RESCUE/NARROW_SILENT_RESCUE — re-registering it " \
           "restores the double-report this test exists to prevent"
  end
end
