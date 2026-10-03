# frozen_string_literal: true

require "minitest/autorun"
require "master"

# The agent must never rewrite the constitution it is judged by or the spine
# that folds its effects. These pin that block — and that ordinary paths still
# pass, so the guard is a scalpel, not a wall.
class ImmutablePathsTest < Minitest::Test
  IMMUTABLE = %w[data/rules.yml data/soul.yml lib/core.rb lib/core/].freeze

  def constitution
    rules = [Master::Core::Constitution.immutable_paths_rule(IMMUTABLE)]
    Master::Core::Constitution.new(rules:)
  end

  def admit(effect) = constitution.admit(effect, nil)

  def assert_blocked(effect, by:)
    verdict = admit(effect)
    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal by, verdict.by
  end

  def assert_allowed(effect)
    assert_instance_of Master::Core::Verdict::Allow, admit(effect)
  end

  def test_write_to_constitution_is_blocked
    assert_blocked Master::Core::Effect.write("data/rules.yml", "laws: []\n"), by: :immutable_paths
  end

  def test_write_anywhere_under_the_spine_is_blocked
    assert_blocked Master::Core::Effect.write("lib/core/world.rb", "# hijack\n"), by: :immutable_paths
  end

  # The entrypoint is a file beside the directory, not inside it. Guarding only
  # `lib/core/` would leave VERBS, Effect and Secret rewritable by an effect.
  def test_write_to_the_spine_entrypoint_is_blocked
    assert_blocked Master::Core::Effect.write("lib/core.rb", "# hijack\n"), by: :immutable_paths
  end

  def test_leading_dot_slash_still_matches
    assert_blocked Master::Core::Effect.write("./data/soul.yml", "x"), by: :immutable_paths
  end

  def test_dot_and_parent_segments_cannot_walk_onto_an_immutable_file
    assert_blocked Master::Core::Effect.write("data/./soul.yml", "x"), by: :immutable_paths
    assert_blocked Master::Core::Effect.write("data/foo/../soul.yml", "x"), by: :immutable_paths
  end

  def test_git_stage_of_immutable_path_is_blocked
    effect = Master::Core::Effect.git(:stage, paths: ["lib/core/fold.rb"])
    assert_blocked effect, by: :immutable_paths
  end

  def test_ordinary_write_passes
    assert_allowed Master::Core::Effect.write("lib/app/thing.rb", "A = 1\n")
  end

  def test_sibling_of_immutable_file_is_not_blocked
    # "lib/core/" guards the tree and "lib/core.rb" is an exact match; a file
    # merely prefixed "core" is neither.
    assert_allowed Master::Core::Effect.write("lib/coreish.rb", "A = 1\n")
  end
end
