# frozen_string_literal: true

require_relative "test_helper"

# TODO.md, Scanner noise: "38 of rake selfcheck's 76 findings are false positives
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

  # --- NO_GOD_CLASS -------------------------------------------------------
  # The line branch counted raw AST span, charging for rationale comments —
  # the counter DENSITY and lint:spine already retired. Core::Constitution
  # read 348 under it while holding 250 code lines, and the resulting
  # self_violation halted every /through fix stage (2026-08-18). Both
  # directions: comments never breach, code still does.

  def test_god_class_line_limit_does_not_charge_for_comments
    body = (["  # rationale line"] * 320 + ["  def call = :ok"]).join("\n")
    source = "class WellExplained\n#{body}\nend\n"

    assert_empty findings(:NO_GOD_CLASS, source), "comment lines counted as class size"
  end

  def test_god_class_line_limit_still_fires_on_code
    long_method = ->(i) { "  def m#{i}\n" + (["    x = compute"] * 105).join("\n") + "\n  end" }
    source = "class Sprawl\n#{3.times.map { |i| long_method.call(i) }.join("\n")}\nend\n"
    hits = findings(:NO_GOD_CLASS, source)

    refute_empty hits, "a 320-code-line class must still be a finding"
    assert_match(/code lines/, hits.first[:message])
  end


# --- DOUBLE_BRACKET ----------------------------------------------------
# [[ ]] is a keyword in zsh and bash, not in POSIX sh — telling an sh
# script to use it is a syntax error prescription.
def test_double_bracket_leaves_posix_sh_alone
  sh = "#!/bin/sh
if [ -f x ]; then echo ok; fi
"
  assert_empty findings(:DOUBLE_BRACKET, sh, path: "script.sh")
end

def test_double_bracket_still_fires_on_zsh
  zsh = "#!/usr/bin/env zsh
if [ -f x ]; then echo ok; fi
"
  refute_empty findings(:DOUBLE_BRACKET, zsh, path: "script.zsh")
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

  # --- veto unfinished ----------------------------------------------------
  # Was "\.\.\.|TODO|FIXME|pending". It fired 119 times in lib/ and was wrong
  # 119 times: 49 the word "pending" (an order state in VALID_STATES, and the
  # inside of depending/spending), 41 an ellipsis in prose or documented syntax,
  # 26 Ruby's exclusive range, 3 the source of the rules that detect TODO.
  #
  # Zero real findings, at :veto — the strongest severity there is. A veto that
  # is wrong every time does not gate anything; it teaches the reader that a
  # veto is noise. Narrowed 2026-08-12 to 0 in lib/.

  def test_veto_unfinished_ignores_ruby_range_pending_and_quoted_markers
    [
      %(dropped = @entries[0...(@entries.length - keep.length)]\n),
      %((1...lines.length).each { |i| check(i) }\n),
      %(@pending = []\n),
      %(VALID_STATES = %w[pending running done error].freeze\n),
      %(# constant from lib/review and depending on its load order\n),
      %(text + "\\n... [truncated]"\n),
      %(scan_lines(src, /\\b(TODO|FIXME|HACK|XXX)\\b/, message: "unresolved marker")\n),
    ].each do |source|
      assert_empty findings(:veto_patterns, source),
                   "#{source.inspect} is ordinary Ruby, not unfinished work"
    end
  end

  # The half a narrowing has to prove: a real marker and a real stub still veto.
  def test_veto_unfinished_still_catches_a_marker_and_a_stub
    refute_empty findings(:veto_patterns, %(# TODO: wire this up\n))
    refute_empty findings(:veto_patterns, %(  # FIXME broken since the merge\n))
    refute_empty findings(:veto_patterns, %(def stub\n  ...\nend\n))
  end

  # --- learned_smells must not restate a registered rule ------------------
  # data/rules.yml's learned_smells layer re-applies raw regexes on top of the
  # registered rules. Two of the ten were copies: `long_line` produced 334
  # findings across lib/ of which THREE were at a line no other rule reports —
  # and all three were in lib/io/llm.rb, which LONG_LINE deliberately exempts, so
  # the copy was 331 duplicates plus a silent override of an exemption.
  # `debug_output` carried the same id as the registered rule, making its findings
  # indistinguishable rather than merely doubled.
  #
  # The other eight are the only implementation of what they detect and stay.

  def test_no_learned_smell_shares_an_id_with_a_registered_rule
    registered = scanner.rules.map { |rule| rule.id.to_s.downcase }
    clashing = learned_smell_ids.select { |id| registered.include?(id.downcase) }

    assert_empty clashing,
                 "a learned_smell restates a registered rule, so both fire on the same line and " \
                 "the findings cannot be told apart: #{clashing.join(', ')}"
  end

  # The substantive half. An id can differ and the detection still be a copy —
  # LONG_LINE vs long_line was exactly that.
  def test_no_learned_smell_reports_what_a_registered_rule_already_reports
    source = "x = 1\n#{'a' * 130}\n"
    findings = scanner.rules.flat_map do |rule|
      next [] unless rule.respond_to?(:check)

      Array(rule.check(source, path: "lib/sample.rb")).map { |f| [f[:line], rule.id.to_s.downcase] }
    rescue StandardError # scan: intentional — a raising rule has its own dedicated test (RaisingRule); here it reads as no findings
      []
    end
    long = findings.select { |line, _| line == 2 }.map(&:last).uniq

    assert_equal 1, long.size,
                 "more than one rule reports the same long line: #{long.join(', ')}"
  end

  def learned_smell_ids
    YAML.safe_load_file(File.expand_path("../data/rules.yml", __dir__), aliases: true)
        .fetch("learned_smells", []).map { |smell| smell["id"].to_s }
  end

  # --- NO_PUTS's exemption survived a directory rename --------------------
  # It read `/now/cli` and lib/now/ was renamed to lib/cli/ in 693d2630d. The
  # exemption kept pointing at the old address, so 105 findings appeared in
  # selfcheck's largest actionable bucket — every one in lib/cli/, 100 of them in
  # lib/cli/cli/, all of them decisions the rule's author had already made.

  def test_no_puts_still_exempts_the_cli_entry_layer
    assert_empty findings(:NO_PUTS, %(  puts "hello"\n), path: "lib/cli/cli/repl_flow.rb")
    assert_empty findings(:NO_PUTS, %(  puts "hello"\n), path: "MASTER/bin/master")
  end

  def test_no_puts_still_catches_a_bare_puts_in_library_code
    refute_empty findings(:NO_PUTS, %(  puts "hello"\n), path: "lib/ground/rules.rb")
  end

  # --- veto sql_injection -------------------------------------------------
  # Was `execute|query.*#\{`, which binds as `(execute)|(query.*#\{)` — so the
  # bare word `execute` anywhere on a line was an unconditional merge blocker.
  # 87 findings in lib/, all read, 0 real: method names (execute_job,
  # pre_execute?), the parameterized form the rule prescribes, a log line, and a
  # comment. The one that looked real interpolated a WHERE clause built entirely
  # from "col = ?" literals with every value in args. Narrowed 2026-08-12 to 0.

  def test_veto_sql_injection_ignores_method_names_and_the_parameterized_form
    [
      %(def execute_resync(lines)\n),
      %(result = execute_job(job)\n),
      %(@bus&.publish("review:blocked", phase: "post_execute")\n),
      %(recent = @db.execute("SELECT event_type FROM events WHERE ts >= ?", [cutoff])\n),
      %(@db.execute(<<~SQL, args).map { |row| row_for(row) }\n),
      %(render("context: gathering for query=\#{query[0, 60]}", mode: :dim)\n),
    ].each do |source|
      assert_empty findings(:veto_patterns, source),
                   "#{source.inspect} is a method name or the parameterized form"
    end
  end

  def test_veto_sql_injection_still_catches_interpolated_sql
    refute_empty findings(:veto_patterns, %(@db.execute("SELECT * FROM t WHERE id = \#{id}")\n))
    refute_empty findings(:veto_patterns, %(@db.execute_batch("DROP TABLE \#{table}")\n))
    # A single quote inside the double-quoted SQL — the classic injection shape.
    # The old `["'][^"']*` class stopped at that quote and missed it entirely.
    refute_empty findings(:veto_patterns, %(db.query("DELETE FROM x WHERE name='\#{name}'")\n))
  end

  # --- veto unsafe_calls, second narrowing --------------------------------
  # 23 findings in lib/ -> 3. The 20 removed: 9 markdown fences inside Ruby
  # strings, 6 markdown code spans in prose, 2 Shellwords.escape'd backticks,
  # 2 Open3 arg-array calls, 1 string wrapped in backticks for display. All four
  # of those shapes are either prose or the fix this rule prescribes.

  def test_veto_unsafe_calls_ignores_markdown_and_escaped_shell_outs
    [
      %([["```\#{lang}", *lines, "```"], lines.size]\n),
      %(parts << "Code:\\n```\\n\#{ctx[:code]}\\n```" if ctx[:code]\n),
      %(md << "## `\#{rel}`"\n),
      %(reason: "recent fix `\#{rule_id}` touched a performance smell"\n),
      %(out = `git -C \#{Shellwords.escape(@root)} status --porcelain`\n),
      %(Open3.capture2e("node", "--input-type=\#{mode}", "--check", stdin_data: src)\n),
    ].each do |source|
      assert_empty findings(:veto_patterns, source),
                   "#{source.inspect} is markdown, or the escaping this rule prescribes"
    end
  end

  def test_veto_unsafe_calls_still_catches_a_shell_out_with_interpolation
    refute_empty findings(:veto_patterns, %(out = `\#{cmd} 2>/dev/null`\n))
    refute_empty findings(:veto_patterns, %(`ps x -o pid= -U \#{user} 2>/dev/null`.each_line { |l| l }\n))
    refute_empty findings(:veto_patterns, %(%x{ls \#{dir}}\n))
    refute_empty findings(:veto_patterns, %(Open3.capture2("ls \#{dir}")\n))
    # Quoting an interpolated path inside a shell string does not make it safe.
    refute_empty findings(:veto_patterns, %(system("rm -rf '\#{directory}'")\n))
  end

  # --- veto patterns and comments ------------------------------------------
  # VetoPatternRule scanned raw source, so a comment describing a shell
  # interpolation vetoed the file that explained it — the same defect
  # without_comment_lines was written for on the declarative side. It is now
  # per-pattern: unfinished declares reads_comments, because a work marker lives
  # in a comment; nothing else does.

  def test_a_comment_describing_a_shell_out_is_not_a_shell_out
    assert_empty findings(:veto_patterns, %(  # the old form was `\#{cmd} 2>/dev/null` here\n))
    assert_empty findings(:veto_patterns, %(  # never write system("rm -rf \#{d}") in this tree\n))
  end

  def test_unfinished_still_reads_comments_because_that_is_where_markers_live
    refute_empty findings(:veto_patterns, %(  # TODO: this must still be caught\n))
  end

  # race_conditions was `if.*\n.*=.*\n.*if` and scan_lines feeds one line at a
  # time, so it needed three lines and could never see two. Deleted 2026-08-12
  # after never having fired; check-then-act detection needs an AST rule and is
  # tracked in TODO.md. This asserts it is gone rather than silently dead.
  # A newline inside a negated class — `[^`\n]*` — is the opposite: it says "stay
  # on this line". Only a \n outside a character class demands one. The first
  # version of this test missed that and failed on two healthy patterns, which is
  # the instrument being wrong rather than the law.
  def self.requires_a_newline?(detect)
    detect.to_s.gsub(/\[\^?(?:\\.|[^\]])*\]/, "").include?('\n')
  end

  def test_no_veto_pattern_needs_more_than_one_line
    multiline = Master.load_rules.fetch("veto_patterns", {}).filter_map do |name, spec|
      name if self.class.requires_a_newline?(spec["detect"])
    end

    assert_empty multiline,
                 "these veto patterns span lines, and scan_lines matches one line at a time, " \
                 "so they can never fire: #{multiline.join(', ')}"
  end

  # The detector above only means something if it still recognises the pattern
  # that was deleted for exactly this.
  def test_the_multiline_detector_recognises_the_deleted_race_conditions_pattern
    assert self.class.requires_a_newline?('if.*\n.*=.*\n.*if'),
           "the check no longer catches the pattern it was written for"
    refute self.class.requires_a_newline?('`[^`\n]*#\{'),
           "a newline inside a negated class means stay on this line, not span lines"
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

  # The shape a line-walking predicate misses: the line it lands on is `end`.
  def test_an_empty_rescue_body_is_still_a_discard
    {
      "rescue\n" => :SILENT_RESCUE,
      "rescue StandardError\n" => :SILENT_RESCUE,
      "rescue Errno::ESRCH\n" => :NARROW_SILENT_RESCUE,
    }.each do |clause, owner|
      source = "def probe\n  work\n#{clause}end\n"

      assert_equal [owner.to_s], discard_reporters(source),
                   "an empty #{clause.strip.inspect} body discards the error and says nothing"
    end
  end

  # NO_DEBUG and TODO_FIXME exempt this directory because their patterns are
  # code in it — `binding.pry` appears as a regex literal. SILENT_RESCUE matches
  # a line opening with `rescue`, which no regex literal does, so it has no such
  # claim and takes the whole directory out of its own reach.
  def test_the_scan_rules_directory_is_not_exempt
    source = rescue_source("rescue StandardError\n")

    refute_empty findings(:SILENT_RESCUE, source, path: "lib/review/scan/rules/example_rules.rb"),
                 "the scanner's own rules are subject to the rescue rules"
  end

  # handled_body? has to name all three spellings itself; two of them otherwise
  # fall through discard_token? and reach the right verdict for the wrong reason.
  def test_swallow_log_is_recognised_however_it_is_spelled
    ["Swallow.log(e)", "Ground::Swallow.log(e)", "Master::Ground::Swallow.log(e)"].each do |call|
      source = "def probe\n  work\nrescue StandardError => e\n  #{call}\n  nil\nend\n"

      assert_empty discard_reporters(source), "#{call} is a report, not a discard"
    end
  end

  # --- a rule that raises must not read as a clean file ----------------------
  class RaisingRule < Master::Review::Scan::Rule
    def self.auto_build? = false

    def initialize
      super()
      @id = "PROBE_RAISER"
    end

    def check_ast(_ast, _code, path:) = raise("check_ast is broken")
  end

  # limit far above the log's size: at 200 the window saturated after two
  # hundred runs of this very test and before == after forever.
  def test_a_rule_that_raises_reports_the_failure_it_swallows
    before = Master::Ground::Swallow.recent(limit: 1_000_000, context: "TestScanRuleFalsePositives::RaisingRule#check_ast").size
    result = RaisingRule.new.check("x = 1\n", path: File.join(Master::ROOT, "lib/example.rb"))
    after = Master::Ground::Swallow.recent(limit: 1_000_000, context: "TestScanRuleFalsePositives::RaisingRule#check_ast")

    assert_empty result, "the scan continues past a broken rule"
    assert_operator after.size, :>, before, "and the broken rule is on the record"
    assert_equal "load_bearing", after.last["severity"]
  end

  # --- line-scoped laws reading comments -------------------------------------
  #
  # A detector over raw lines flags prose about a construct as the construct:
  # "# a bare rescue" was an error-severity finding. The yaml bridge learned to
  # skip comment lines once; when FAIL_VISIBLY, BARE_RESCUE (folded into it) and
  # GUARD_EXPENSIVE_OPS moved to law/, the lesson stayed behind and the same
  # false positives came back through the law bridge. Comment skipping lives in
  # Law's own line scan now, keyed on the file's comment syntax, with
  # reads_comments as the opt-in for rules whose subject IS comments.

  def bridge = scanner.rules.find { |r| r.id.to_s == "law_bridge" } || raise("bridge rule is not registered")

  LINE_RULES = %w[FAIL_VISIBLY GUARD_EXPENSIVE_OPS].freeze

  def bridge_findings(source, path: "lib/example.rb")
    Array(bridge.check(source, path: File.join(Master::ROOT, path)))
      .map { |f| f[:rule].to_s }.select { |id| LINE_RULES.include?(id) }
  end

  def test_a_comment_naming_a_forbidden_construct_is_not_a_finding
    [
      ["# `rescue Exception` falls to SILENT_RESCUE's non-narrow branch\n", "lib/example.rb"],
      ["  # a bare rescue\n", "lib/example.rb"],
      ["# Rotate rather than truncate-in-place\n", "lib/example.rb"],
      ["  // rm -rf in a JS comment\n", "web/example.js"],
    ].each do |source, path|
      assert_empty bridge_findings(source, path:), "#{source.strip.inspect} is prose, not code"
    end
  end

  def test_the_same_constructs_in_code_are_still_findings
    assert_includes bridge_findings("def probe\n  work\nrescue\n  nil\nend\n"), "FAIL_VISIBLY"
    assert_includes bridge_findings("def probe\n  work\nrescue Exception\n  nil\nend\n"), "FAIL_VISIBLY"
    assert_includes bridge_findings("  Item.delete_all\n"), "GUARD_EXPENSIVE_OPS"
  end

  # `@transforms << :bare_rescue` in the autofixer that repairs bare rescues was an
  # error-severity finding against itself, recorded in TODO.md as noise rather than
  # fixed. A symbol is not a rescue clause.
  def test_a_symbol_named_bare_rescue_is_not_a_bare_rescue
    refute_includes bridge_findings("  @transforms << :bare_rescue\n"), "FAIL_VISIBLY"
    refute_includes bridge_findings("  def bare_rescue\n"), "FAIL_VISIBLY"
  end

  # The rules whose subject is comments keep their reach: a comment that IS the
  # violation still fires through the same comment-skipping scan.
  def test_comment_reading_laws_still_see_comments
    hits = Array(bridge.check("# increment counter\n", path: File.join(Master::ROOT, "lib/example.rb")))
    assert(hits.any? { |f| f[:rule] == "WHY_NOT_WHAT" }, "WHY_NOT_WHAT reads comments by design")
  end

  def test_the_deleted_rule_does_not_come_back
    refute scanner.rules.any? { |r| r.id.to_s == "EMPTY_RESCUE" },
           "EMPTY_RESCUE was collapsed into SILENT_RESCUE/NARROW_SILENT_RESCUE — re-registering it " \
           "restores the double-report this test exists to prevent"
  end

  def test_ascii_dividers_in_tests_and_assertions_are_not_decorations
    assert_empty findings(:NO_ASCII_LINE_ART, "assert_equal '===', sep\n", path: "test/example.rb")
    assert_empty findings(:NO_ASCII_LINE_ART, "assert_match(/---/, line)\n")
    assert_empty findings(:NO_ASCII_LINE_ART, "---\nkey: 1\n", path: "data/example.yml")
  end

  def test_ascii_dividers_in_lib_prose_still_fire
    refute_empty findings(:NO_ASCII_LINE_ART, "# ===== section =====\n")
  end
end
