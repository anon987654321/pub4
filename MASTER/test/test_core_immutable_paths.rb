# frozen_string_literal: true

require "minitest/autorun"
require "master"

# The agent must never rewrite the constitution it is judged by or the spine
# that folds its effects. These pin that block — and that ordinary paths still
# pass, so the guard is a scalpel, not a wall.
class ImmutablePathsTest < Minitest::Test
  IMMUTABLE = %w[lib/core.rb lib/core/ lib/ground/pledge.rb].freeze

  def constitution(workspace_root: Master::ROOT)
    rules = [Master::Core::Constitution.immutable_paths_rule(
      IMMUTABLE, master_root: Master::ROOT, workspace_root:
    )]
    Master::Core::Constitution.new(laws: rules)
  end

  def admit(effect, workspace_root: Master::ROOT) = constitution(workspace_root:).admit(effect, nil)

  def assert_blocked(effect, by:, workspace_root: Master::ROOT)
    verdict = admit(effect, workspace_root:)
    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal by, verdict.by
  end

  def assert_allowed(effect, workspace_root: Master::ROOT)
    assert_instance_of Master::Core::Verdict::Allow, admit(effect, workspace_root:)
  end

  def test_real_manifest_protects_the_openbsd_pledge_boundary
    sacred = Master::Core::Constitution::Paths.sacred_paths(root: Master::ROOT)
    assert_includes sacred, "lib/ground/pledge.rb"

    law = Master::Core::Constitution.immutable_paths_rule(
      sacred, master_root: Master::ROOT, workspace_root: Master::ROOT
    )
    verdict = law.judge.call(
      Master::Core::Effect.write("lib/ground/pledge.rb", "# bypass\n"),
      nil,
    )

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :immutable_paths, verdict.by
  end

  def test_law_catalogue_is_editable_under_invariant_admission
    assert_allowed Master::Core::Effect.write("data/laws.yml", "laws: []\n")
    assert_allowed Master::Core::Effect.write("data/soul.yml", "absolute:\n  sacred_paths: []\n")
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

  def test_absolute_master_root_soul_path_is_editable
    path = File.join(Master::ROOT, "data/soul.yml")
    assert_allowed Master::Core::Effect.write(path, "absolute:\n  sacred_paths: []\n")
  end

  def test_absolute_repository_path_with_master_prefix_allows_law_catalogue_edits
    path = File.join(Master::REPO_ROOT, "MASTER", "data", "laws.yml")
    assert_allowed Master::Core::Effect.write(path, "law_catalogue: {}\n")
  end

  def test_repo_relative_master_path_allows_law_catalogue_edits
    effect = Master::Core::Effect.write("MASTER/data/laws.yml", "law_catalogue: {}\n")
    assert_allowed effect, workspace_root: Master::REPO_ROOT
  end

  def test_repo_root_file_with_the_same_relative_name_is_not_overblocked
    effect = Master::Core::Effect.write("data/laws.yml", "x")
    assert_allowed effect, workspace_root: Master::REPO_ROOT
  end

  def test_absolute_git_stage_of_sacred_path_is_blocked
    path = File.join(Master::REPO_ROOT, "MASTER", "lib", "core", "fold.rb")
    effect = Master::Core::Effect.git(:stage, paths: [path])
    assert_blocked effect, by: :immutable_paths
  end

  def test_dot_and_parent_segments_resolve_to_editable_law_catalogue
    assert_allowed Master::Core::Effect.write("data/./laws.yml", "law_catalogue: {}\n")
    assert_allowed Master::Core::Effect.write("data/foo/../laws.yml", "law_catalogue: {}\n")
  end

  def test_git_stage_of_immutable_path_is_blocked
    effect = Master::Core::Effect.git(:stage, paths: ["lib/core/fold.rb"])
    assert_blocked effect, by: :immutable_paths
  end

  def test_real_manifest_does_not_make_configuration_or_scanner_paths_immutable
    sacred = Master::Core::Constitution::Paths.sacred_paths(root: Master::ROOT)
    refute sacred.any? { |entry| entry == "data/" || entry == "data" || entry == "data/soul.yml" }
    refute sacred.any? { |entry| entry.start_with?("lib/review/scan/") }

    law = Master::Core::Constitution.immutable_paths_rule(
      sacred, master_root: Master::ROOT, workspace_root: Master::ROOT
    )
    [
      Master::Core::Effect.write("data/laws.yml", "law_catalogue: {}\n"),
      Master::Core::Effect.write("data/soul.yml", "absolute:\n  sacred_paths: []\n"),
      Master::Core::Effect.write("lib/review/scan/law.rb", "# scanner code may evolve\n"),
    ].each do |effect|
      assert_instance_of Master::Core::Verdict::Allow, law.judge.call(effect, nil)
    end
  end

  def test_ordinary_write_passes
    assert_allowed Master::Core::Effect.write("lib/app/thing.rb", "A = 1\n")
  end

  def test_sibling_of_immutable_file_is_not_blocked
    # "lib/core/" guards the tree and "lib/core.rb" is an exact match; a file
    # merely prefixed "core" is neither.
    assert_allowed Master::Core::Effect.write("lib/coreish.rb", "A = 1\n")
  end

  def test_non_boolean_capability_result_fails_closed
    capabilities = Object.new
    capabilities.define_singleton_method(:allow?) { |_capability| :yes }
    constitution = Master::Core::Constitution.new(laws: [], capabilities:)
    verdict = constitution.admit(Master::Core::Effect.write("lib/app/thing.rb", "A = 1\n"), nil)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :capability, verdict.by
  end

  def test_law_applicability_exception_fails_closed
    law = Object.new
    law.define_singleton_method(:id) { :broken }
    law.define_singleton_method(:watches?) { |_verb| raise "sensitive applicability details" }
    verdict = Master::Core::Constitution.new(laws: [law]).admit(
      Master::Core::Effect.write("lib/app/thing.rb", "A = 1\n"), nil
    )

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :law_evaluator_error, verdict.by
    refute_includes verdict.reason, "sensitive applicability details"
  end

  def test_law_evaluator_exception_fails_closed
    law = Master::Core::Constitution::Law.new(
      id: :broken,
      verbs: %i[write],
      judge: ->(_effect, _memory) { raise "sensitive evaluator details" },
    )
    verdict = Master::Core::Constitution.new(laws: [law]).admit(
      Master::Core::Effect.write("lib/app/thing.rb", "A = 1\n"), nil
    )

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :law_evaluator_error, verdict.by
    refute_includes verdict.reason, "sensitive evaluator details"
  end

  def test_invalid_non_nil_law_result_fails_closed
    law = Master::Core::Constitution::Law.new(
      id: :broken,
      verbs: %i[write],
      judge: ->(_effect, _memory) { :allow },
    )
    verdict = Master::Core::Constitution.new(laws: [law]).admit(
      Master::Core::Effect.write("lib/app/thing.rb", "A = 1\n"), nil
    )

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :law_evaluator_error, verdict.by
  end
end
