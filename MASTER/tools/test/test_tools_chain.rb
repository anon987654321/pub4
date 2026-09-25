# frozen_string_literal: true

require_relative "tool_test_helper"
require "tmpdir"
require_relative "../preprompt/lib/chain"

# preprompt refuses an option a model does not accept rather than letting the API
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
      input_keys: %w[prompt aspect_ratio output_format safety_tolerance seed input_image],
    },
    # FLUX 2 takes references as a LIST. A validator that knows only the
    # singular refuses every chain built on the current generation.
    "black-forest-labs/flux-2-max" => {
      input_keys: %w[prompt input_images aspect_ratio output_format output_quality seed],
    },
    "black-forest-labs/flux-schnell" => {
      input_keys: %w[prompt aspect_ratio output_format seed num_inference_steps],
    },
  }.freeze

  def capability_for = ->(model) { CAPS.fetch(model, { input_keys: %w[prompt seed] }) }

  def chain_from(yaml, name: "probe")
    Preprompt::Chain.parse(YAML.safe_load(yaml), name: name)
  end

  def problems_for(yaml)
    Preprompt::Chain.problems(chain_from(yaml), capability_for: capability_for)
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

    # The message lists every spelling a model might use, not just the two FLUX
    # ones. It grew when the chain reached outside that family: Depth Anything
    # takes `image`, IC-Light takes `subject_image`, the control models take
    # `control_image`, and against a two-name list all three read as "nowhere to
    # put an image" — refusing exactly the chains worth building.
    assert(problems.any? { |p| p.include?("declares none of") && p.include?("input_image") },
           "expected a refusal naming the image-input keys, got #{problems.inspect}")
  end

  def test_a_stage_inheriting_an_image_into_a_flux_2_model_is_allowed
    problems = problems_for(<<~YML)
      stages:
        - name: establish
          model: black-forest-labs/flux-2-max
          prompt: a quayside
        - name: restyle
          model: black-forest-labs/flux-2-max
          prompt: as a print
          inherits: [image]
    YML

    assert_empty problems,
                 "flux-2 spells it input_images; refusing that refuses the entire current generation"
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
    assert_raises(Preprompt::Chain::Invalid) { chain_from("description: nothing here") }
    assert_raises(Preprompt::Chain::Invalid) { chain_from("stages: []") }
  end

  # The shipped chains are part of the tree and have to stay valid, or the first
  # thing anyone runs is broken.
  def test_every_shipped_chain_parses
    names = Preprompt::Chain.available
    refute_empty names, "no chains found — the glob is wrong, not the tree"

    names.each do |name|
      chain = Preprompt::Chain.load(name)
      refute_empty chain[:stages], "#{name} has no stages"
      assert chain[:description], "#{name} has no description; `chains --list` would show a blank"
    end
  end

  def test_the_plan_names_every_stage_in_order
    plan = Preprompt::Chain.plan(chain_from(<<~YML))
      stages:
        - { name: alpha, model: black-forest-labs/flux-schnell, prompt: one }
        - { name: beta, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [image] }
    YML

    assert_equal 2, plan.length
    assert_includes plan[0], "alpha"
    assert_includes plan[1], "beta"
    assert_includes plan[1], "image", "the plan has to say what each stage carries forward"
  end
  # The carry-forward, which is the one thing a chain must get right and the one
  # thing that fails silently: a model handed no image generates from the prompt
  # and returns something entirely plausible. Chain.run takes the performer as
  # an argument precisely so this can be checked without spending anything.
  def recorder
    calls = []
    perform = lambda do |stage:, index:, total:, image:, seed:, references: []|
      calls << { name: stage.name, image: image, seed: seed, references: references, index: index, total: total }
      { path: "out-#{index + 1}-#{stage.name}.jpg", seed: 1000 + index }
    end
    [calls, perform]
  end

  # The consistency spine: a stage inheriting references is handed every file the
  # chain has produced so far, so a character accumulates across stages instead of
  # being held only by the one frame before. A stage that does not ask gets none.
  def test_a_stage_inheriting_references_gets_every_earlier_output
    calls, perform = recorder
    chain = chain_from(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-2-max, prompt: one }
        - { name: b, model: black-forest-labs/flux-2-max, prompt: two }
        - { name: c, model: black-forest-labs/flux-2-max, prompt: three, inherits: [references] }
    YML

    Preprompt::Chain.run(chain, perform: perform)

    assert_empty calls[1][:references], "a stage that does not inherit references is given none"
    assert_equal %w[out-1-a.jpg out-2-b.jpg], calls[2][:references]
  end

  def test_each_stage_receives_the_previous_stages_file
    calls, perform = recorder
    chain = chain_from(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one }
        - { name: b, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [image] }
        - { name: c, model: black-forest-labs/flux-kontext-pro, prompt: three, inherits: [image] }
    YML

    produced = Preprompt::Chain.run(chain, perform: perform)

    assert_nil calls[0][:image], "the first stage has nothing to inherit"
    assert_equal "out-1-a.jpg", calls[1][:image], "stage 2 must be handed stage 1s file"
    assert_equal "out-2-b.jpg", calls[2][:image], "stage 3 must be handed stage 2s file"
    assert_equal %w[out-1-a.jpg out-2-b.jpg out-3-c.jpg], produced,
                 "every intermediate is kept, not just the last frame"
  end

  def test_a_stage_that_inherits_nothing_is_handed_nothing
    calls, perform = recorder
    chain = chain_from(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one }
        - { name: b, model: black-forest-labs/flux-kontext-pro, prompt: two }
    YML

    Preprompt::Chain.run(chain, perform: perform)

    assert_nil calls[1][:image],
               "a stage that declares no inheritance must not silently receive the previous frame"
  end

  def test_seed_carries_only_when_inherited
    calls, perform = recorder
    chain = chain_from(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one }
        - { name: b, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [seed] }
        - { name: c, model: black-forest-labs/flux-kontext-pro, prompt: three }
    YML

    Preprompt::Chain.run(chain, perform: perform)

    assert_equal 1000, calls[1][:seed], "stage 2 inherits the seed stage 1 used"
    assert_nil calls[2][:seed], "stage 3 does not inherit, so it gets none"
  end

  def test_until_stops_after_the_named_stage
    calls, perform = recorder
    chain = chain_from(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one }
        - { name: b, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [image] }
        - { name: c, model: black-forest-labs/flux-kontext-pro, prompt: three, inherits: [image] }
    YML

    produced = Preprompt::Chain.run(chain, perform: perform, until_stage: "b")

    assert_equal 2, calls.length, "--until b must not run c"
    assert_equal %w[out-1-a.jpg out-2-b.jpg], produced
  end

  # A stage that fails returns nil, and the run stops rather than handing the
  # next stage a file that does not exist.
  def test_a_failed_stage_stops_the_run_and_keeps_what_came_before
    chain = chain_from(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one }
        - { name: b, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [image] }
        - { name: c, model: black-forest-labs/flux-kontext-pro, prompt: three, inherits: [image] }
    YML
    perform = lambda do |stage:, index:, total:, image:, seed:, references: []|
      next nil if stage.name == "b"

      { path: "out-#{index + 1}.jpg", seed: 1 }
    end

    produced = Preprompt::Chain.run(chain, perform: perform)

    assert_equal %w[out-1.jpg], produced, "stage 1 is kept; nothing after the failure runs"
  end

  # --- resuming ------------------------------------------------------------

  THREE_STAGES = <<~YML
    stages:
      - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one }
      - { name: b, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [image, seed] }
      - { name: c, model: black-forest-labs/flux-kontext-pro, prompt: three, inherits: [image] }
  YML

  # A stage before --from has been paid for, so it is read back and not made
  # again, and the stage after it inherits the resumed file and seed.
  def test_from_stage_resumes_earlier_stages_instead_of_performing_them
    calls, perform = recorder
    Dir.mktmpdir do |dir|
      earlier = File.join(dir, "out-1-a.jpg")
      File.write(earlier, "frame")
      resume = ->(stage:, index:) { { path: earlier, seed: 77 } }

      produced = Preprompt::Chain.run(chain_from(THREE_STAGES), perform: perform, from_stage: "b", resume: resume)

      assert_equal %w[b c], calls.map { |call| call[:name] }, "stage a was performed again"
      assert_equal earlier, calls.first[:image]
      assert_equal 77, calls.first[:seed]
      assert_equal earlier, produced.first
    end
  end

  def test_resuming_a_stage_with_nothing_on_disk_stops_the_run
    _, perform = recorder
    resume = ->(stage:, index:) { { path: "/nonexistent/out-1-a.jpg" } }

    assert_raises(Preprompt::Chain::NothingToResume) do
      Preprompt::Chain.run(chain_from(THREE_STAGES), perform: perform, from_stage: "b", resume: resume)
    end
  end

  def test_from_a_stage_the_chain_does_not_have_is_refused
    _, perform = recorder

    assert_raises(Preprompt::Chain::Invalid) do
      Preprompt::Chain.run(chain_from(THREE_STAGES), perform: perform, from_stage: "nope")
    end
  end

  # --- the grade and the bound ---------------------------------------------

  GRADED = <<~YML
    stages:
      - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one }
      - { name: b, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [image], options: { postpro: house } }
  YML

  def test_the_last_stages_postpro_grades_the_chain_when_the_command_line_names_none
    chain = chain_from(GRADED)

    assert_equal "house", Preprompt::Chain.grade_for(chain, produced: %w[a b], requested: nil)
    assert_equal "noir", Preprompt::Chain.grade_for(chain, produced: %w[a b], requested: "noir")
    assert_equal false, Preprompt::Chain.grade_for(chain, produced: %w[a b], requested: false)
    assert_nil Preprompt::Chain.grade_for(chain, produced: %w[a], requested: nil),
               "a chain stopped by --until ends on a frame nobody asked to grade"
  end

  def test_postpro_on_a_stage_before_the_last_is_refused
    assert_empty problems_for(GRADED)
    problems = problems_for(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one, options: { postpro: house } }
        - { name: b, model: black-forest-labs/flux-kontext-pro, prompt: two, inherits: [image] }
    YML

    assert(problems.any? { |p| p.include?("only the last stage") }, problems.inspect)
  end

  def test_a_stage_carries_its_own_timeout_and_a_nonsense_one_is_refused
    timed = chain_from(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one, timeout: 900 }
    YML
    assert_equal 900, timed[:stages].first.timeout
    assert_empty Preprompt::Chain.problems(timed, capability_for: capability_for)

    problems = problems_for(<<~YML)
      stages:
        - { name: a, model: black-forest-labs/flux-kontext-pro, prompt: one, timeout: soon }
    YML
    assert(problems.any? { |p| p.include?("timeout") }, problems.inspect)
  end

  # The YAML's hash rides with the chain, so a frame's sidecar names the recipe.
  def test_a_loaded_chain_carries_the_hash_of_its_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "probe.yml"), THREE_STAGES)
      chain = Preprompt::Chain.load("probe", dir: dir)

      assert_equal Digest::SHA256.file(File.join(dir, "probe.yml")).hexdigest, chain[:sha256]
    end
  end
end
