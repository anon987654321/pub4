# frozen_string_literal: true

# A "Do Not Touch" entry states a conclusion. Conclusions do not rot loudly.
#
# The entry defending the rule shards said they sat near their consumers. The
# four shards had one consumer between them — `load_rules`, which concatenated
# them back into a single hash before any scanner saw them — so the reason was
# false from the day the shards were created, and stayed on the list until an
# operator overrode it by hand in 2026-08. Had the entry named the test its own
# reason implied, that test would have been red from the start.

require "minitest/autorun"
require_relative "../tools/do_not_touch"

class TestDoNotTouch < Minitest::Test
  def self.report = @report ||= Pub4::DoNotTouch.run

  def setup
    @report = self.class.report
  end

  def test_every_entry_names_a_gate_or_says_why_it_cannot
    findings = @report["findings"].map { |row| "entry #{row['entry']}: #{row['message']}" }

    assert_empty findings,
                 "add `— gate: \`rake some:task\`` or `— no gate: <reason>` to the entry:\n  " \
                 "#{findings.join("\n  ")}"
  end

  # A parser that stops matching entries reports every entry as compliant.
  def test_the_parser_still_finds_the_list
    assert_operator @report["entries"], :>=, 10,
                    "only #{@report['entries']} Do Not Touch entries parsed — the heading or the " \
                    "numbering changed and this lint is now checking nothing"
    assert_operator @report["rake_tasks"], :>, 15,
                    "only #{@report['rake_tasks']} rake tasks discovered — `rake -T` failed, so " \
                    "every named task would look missing or every one would look present"
  end

  # The parser read one line per entry, so wrapping an entry to the tree's own
  # 80-column prose width moved its gate reference out of view and the entry
  # reported as naming no gate. Eight of twelve failed that way at once.
  def test_a_wrapped_entry_keeps_its_gate
    doc = <<~MD.lines
      ## Do Not Touch (unless the task requires it)

      1. `lib/core.rb` and `lib/core/` are the fold spine, and they must not
         reach into the application half of `lib/`. — gate:
         `test/test_core_no_lib_backedges.rb`
      2. Secrets live in `/etc/*.env` on the VPS. — no gate: a fact about a
         remote host that nothing in this repo can observe.

      ## Next Section
    MD

    parsed = Pub4::DoNotTouch.parse(doc)

    assert_equal 2, parsed.size
    assert_includes parsed[0][1], "test_core_no_lib_backedges.rb"
    assert_includes parsed[1][1], "remote host"
    assert_empty parsed.flat_map { |number, text| Pub4::DoNotTouch.check(number, text) }
  end

  # Both halves must be able to fail, or the gate is decorative.
  def test_a_missing_gate_is_a_finding
    assert_empty Pub4::DoNotTouch.check("1", "something — gate: `rake lint:spine`")
    refute_empty Pub4::DoNotTouch.check("1", "something — gate: `rake lint:no_such_task`")
    refute_empty Pub4::DoNotTouch.check("1", "something — gate: `test/no_such_test.rb`")
  end

  def test_an_entry_with_no_gate_and_no_reason_is_a_finding
    refute_empty Pub4::DoNotTouch.check("1", "just do not touch it")
    refute_empty Pub4::DoNotTouch.check("1", "do not touch it — no gate: because")
    assert_empty Pub4::DoNotTouch.check(
      "1", "do not touch it — no gate: a fact about a remote host that this repo cannot observe"
    )
  end
end
