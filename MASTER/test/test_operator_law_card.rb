# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# `bin/operator laws <ID> --card` is how an agent reads one Law before writing.
# It broke twice without a test noticing: a require pointed at a renamed file,
# and the declaration walk looked for an `id:` field that laws.yml keys by name.
class TestOperatorLawCard < Minitest::Test
  OPERATOR = File.join(Master::ROOT, "bin", "operator")

  def card(id)
    out, status = Open3.capture2e(OPERATOR, "laws", id, "--card")
    [out, status]
  end

  def test_declared_law_prints_its_statement_and_constitution_digest
    out, status = card("SINGULARITY")
    assert status.success?, out
    assert_includes out, "One source of truth"
    assert_match(/constitution, \h{12}/, out)
  end

  def test_executable_law_resolves_with_its_id
    out, status = card("EACH_WITH_OBJECT")
    assert status.success?, out
    assert_includes out, "law EACH_WITH_OBJECT,"
  end

  def test_declared_only_law_does_not_borrow_an_unrelated_mention
    out, = card("ROBUSTNESS")
    assert_includes out, "no definition found"
  end

  def test_unknown_law_is_refused
    out, status = card("NO_SUCH_LAW")
    refute status.success?
    assert_includes out, "nothing named"
  end
end
