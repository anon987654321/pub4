# frozen_string_literal: true

require_relative "test_helper"

class TestEffectBoundaryContract < Minitest::Test
  def test_every_nonterminal_core_verb_has_a_world_handler
    verbs = Master::Core::VERBS
    handlers = (Master::Core::World.instance_methods(false) +
      Master::Core::World.private_instance_methods(false)).grep(/\Ado_/).map do |name|
      name.to_s.delete_prefix("do_").to_sym
    end

    assert_includes verbs, :done
    assert_equal [], (verbs - [:done] - handlers).sort
    # Git commit is a specialized helper used by the git handler, not a model verb.
    assert_equal [:git_commit], (handlers - (verbs - [:done])).sort
  end

  def test_fold_admits_before_dispatching_and_handles_done_without_world_io
    source = File.read(File.join(Master::ROOT, "lib", "core", "fold.rb"), encoding: "UTF-8")
    assert_operator source.index("@law.admit(effect, @memory)"), :<, source.index("done = apply(turn, admitted)")
    assert_includes source, "if admitted.done?"
  end
end
