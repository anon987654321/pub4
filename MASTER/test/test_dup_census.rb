# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/audit/dup_census"

# A tracked symlink and its target read as one file twice. They cannot diverge, which is the
# failure the census counts, so a symlink is never a member of a duplicate set
# (FUN/zshrc.shared -> OPENBSD/lib/zshrc.shared pushed the count over its ceiling).
class TestDupCensus < Minitest::Test
  def test_no_duplicate_set_holds_a_symlink
    linked = Operator::DupCensus.sets.values.flatten.select { |path| File.symlink?(File.join(Operator::DupCensus::ROOT, path)) }

    assert_empty linked, "symlinks counted as duplicate copies: #{linked.join(", ")}"
  end

  def test_the_tracked_tree_is_at_or_under_the_recorded_ceiling
    assert_operator Operator::DupCensus.sets.size, :<=, Operator::DupCensus.ceiling
  end
end
