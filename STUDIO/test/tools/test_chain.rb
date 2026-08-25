# frozen_string_literal: true

require_relative "../helper"
require_relative "../../repligen/chain"

# repligen refuses an option a model does not accept rather than letting the API
# ignore it, because a request that "works" while silently dropping a setting is
# much harder to notice than a 422. A chain multiplies that: stage 6 failing
# because stage 2 could not produce what stage 3 assumed costs an afternoon and
# a real bill.
#
# So the whole chain is validated before anything is spent, and these are the
# refusals. Every one is checked against a chain that should trip it AND one
# that should not, because a validator that refuses everything is as useless as
# one that refuses nothing.
class TestChain < Minitest::Test
  # The real table, so these tests move when the capabilities do. A stub would
  # let the validator drift from the models it validates against, which is the
  # second-source-of-truth failure this tool already documents elsewhere.
  CAPS = {
    "black-forest-labs/flux-kontext-pro" => {
      input_keys: %w[prompt aspect_ratio output_format safety_tolerance seed input_image]
    },
    "black-forest-labs/flux-schnell" => {
      input_keys: %w[prompt aspect_ratio output_format seed num_inference_steps]
    }
  }.freeze

  def capability_for = ->(model) { CAPS.fetch(model, { input_keys: %w[prompt seed] }) }

  def chain_from(yaml, name: "probe")
    Repligen::Chain.parse(YAML.safe_load(yaml), name: name)
  end

  def problems_for(yaml)
    Repligen::Chain.problems(chain_from(yaml), capability_for: capability_for)
  end

  def test_a_valid_two_stage_chain_has_no_problems
    problems = problems_for(<<~YML)
      stages:
        - name: establish
          model: black-forest-labs/flux-schnell
          prompt: a quayside
        - name: restyle
          model: black-forest-labs/flux-kontext-pro
          prompt: as a silver gelatin print
          inherits: [image]
    YML

    assert_empty problems, "a chain whose every stage is satisfiable must not be refused"
  end

  # The refusal that matters most: a stage expects the previous frame, and is
  # handed to a model with nowhere to put an image. The API would accept the
  # call and generate from the prompt alone, which looks like the chain working.
  def test_a_stage_inheriting_an_image_into_a_model_that_takes_none_is_refused
    problems = problems_for(<<~YML)
      stages:
        - name: establish
          model: black-forest-labs/flux-kontext-pro
          prompt: a quayside
        - name: restyle
          model: black-forest-labs/flux-schnell
          prompt: as a print
          inherits: [image]
    YML

    assert(problems.any? { |p| p.include?("declares no input_image") },
           "expected a refusal naming input_image, got #{problems.inspect}")
  end

  def test_the_first_stage_cannot_inherit
    problems = problems_for(<<~YML)
      stages:
        - name: establish
          model: black-forest-labs/flux-kontext-pro
          prompt: a quayside
          inherits: [image]
    YML

    assert(problems.any? { |p| p.include?("nothing has run yet") })
  end

  def test_an_option_the_model_does_not_accept_is_refused
    problems = problems_for(<<~YML)
      stages:
        - name: establish
          model: black-forest-labs/flux-schnell
          prompt: a quayside
          options:
            safety_tolerance: 3
    YML

    assert(problems.any? { |p| p.include?("safety_tolerance") })
  end

  def test_an_option_the_model_does_accept_is_not_refused
    assert_empty problems_for(<<~YML)
      stages:
        - name: establish
          model: black-forest-labs/flux-kontext-pro
          prompt: a quayside
          options:
            safety_tolerance: 3
    YML
  end

  def test_an_unknown_inherit_is_refused_by_name
    problems = problems_for(<<~YML)
      stages:
        - name: a
          model: black-forest-labs/flux-kontext-pro
          prompt: one
        - name: b
          model: black-forest-labs/flux-kontext-pro
          prompt: two
          inherits: [vibes]
    YML

    assert(problems.any? { |p| p.include?("vibes") && p.include?("image") },
           "the refusal has to name what IS inheritable, or it is a puzzle")
  end

  def test_a_stage_with_no_prompt_and_no_inherited_one_is_refused
    problems = problems_for(<<~YML)
      stages:
        - name: establish
          model: black-forest-labs/flux-kontext-pro
    YML

    assert(problems.any? { |p| p.include?("neither a prompt nor an inherited one") })
  end

  # Not a hard refusal — a long chain that preserves nothing is legal and
  # sometimes wanted. But it drifts, and drift is the reason chains of this
  # shape are usually abandoned rather than debugged.
  def test_a_long_chain_that_preserves_nothing_is_warned_about
    problems = problems_for(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-schnell, prompt: one }
        - { name: b, model: black-forest-labs/flux-schnell, prompt: two }
        - { name: c, model: black-forest-labs/flux-schnell, prompt: three }
    YML

    assert(problems.any? { |p| p.include?("never preserves structure") })
  end

  def test_a_two_stage_chain_that_preserves_nothing_is_left_alone
    problems = problems_for(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-schnell, prompt: one }
        - { name: b, model: black-forest-labs/flux-schnell, prompt: two }
    YML

    assert_empty problems, "two stages is not a drift problem, and warning about it is noise"
  end

  def test_a_malformed_chain_says_so_rather_than_half_running
    assert_raises(Repligen::Chain::Invalid) { chain_from("description: nothing here") }
    assert_raises(Repligen::Chain::Invalid) { chain_from("stages: []") }
  end

  # The shipped chains are part of the tree and have to stay valid, or the first
  # thing anyone runs is broken.
  def test_every_shipped_chain_parses
    names = Repligen::Chain.available
    refute_empty names, "no chains found — the glob is wrong, not the tree"

    names.each do |name|
      chain = Repligen::Chain.load(name)
      refute_empty chain[:stages], "#{name} has no stages"
      assert chain[:description], "#{name} has no description; `chains --list` would show a blank"
    end
  end

  def test_the_plan_names_every_stage_in_order
    plan = Repligen::Chain.plan(chain_from(<<~YML))
      stages:
        - { name: alpha, model: black-forest-labs/flux-schnell, prompt: one }
        - { name: beta, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [image] }
    YML

    assert_equal 2, plan.length
    assert_includes plan[0], "alpha"
    assert_includes plan[1], "beta"
    assert_includes plan[1], "image", "the plan has to say what each stage carries forward"
  end
end
