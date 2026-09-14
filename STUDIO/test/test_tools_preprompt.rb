# frozen_string_literal: true

require_relative "tools_helper"
Studio::Tools.load_tool("preprompt/preprompt.rb")

# preprompt builds an API request out of seven controlled vocabularies and a
# per-model capability table. Everything below the network call is pure, and
# none of it was covered -- including the part that decides which keys reach
# Replicate, where sending a key the model does not take is a 422 and dropping
# one it does take is a silently different picture.
class TestPreprompt < Minitest::Test
  ULTRA = "black-forest-labs/flux-1.1-pro-ultra"
  DEV = "black-forest-labs/flux-dev"
  SCHNELL = "black-forest-labs/flux-schnell"
  KONTEXT = "black-forest-labs/flux-kontext-pro"

  # The house grade is a graded-look default, so a change to it has to be a
  # deliberate edit that fails here first.
  def test_every_generation_is_graded_portrait_unless_the_shell_says_otherwise
    skip "PREPROMPT_POSTPRO is set in this shell" if ENV.key?("PREPROMPT_POSTPRO")

    assert_equal "portrait", HOUSE_POSTPRO
  end

  def test_a_prompt_past_the_word_ceiling_warns_and_one_inside_it_does_not
    _, quiet = capture_io { send(:warn_prompt_length, (["word"] * PROMPT_WORD_CEILING).join(" "), SCHNELL) }
    _, loud = capture_io { send(:warn_prompt_length, (["word"] * (PROMPT_WORD_CEILING + 1)).join(" "), SCHNELL) }

    assert_empty quiet
    assert_match(/#{PROMPT_WORD_CEILING + 1} words/, loud)
  end

  # --- capabilities -------------------------------------------------------

  def test_an_unknown_model_gets_the_conservative_default
    cap = send(:capability_for, "some/model-nobody-configured")

    assert_equal DEFAULT_CAPABILITY, cap
    refute_includes cap[:input_keys], "raw", "the default must not claim knobs it cannot verify"
  end

  def test_every_declared_model_declares_the_keys_its_numeric_knobs_use
    MODEL_CAPABILITIES.each do |model, cap|
      %i[guidance steps].each do |kind|
        key = cap[:"#{kind}_key"]
        next unless key

        assert_includes cap[:input_keys], key,
                        "#{model} accepts --#{kind} but never sends #{key}"
        assert_kind_of Range, cap[:"#{kind}_range"], "#{model} has no range for #{kind}"
        assert_includes cap[:"#{kind}_range"], cap[:"#{kind}_default"],
                        "#{model}'s own default for #{kind} is outside its range"
      end
    end
  end

  def test_the_two_named_models_are_configured
    [PREVIEW_MODEL, FINAL_MODEL].each do |model|
      assert MODEL_CAPABILITIES.key?(model), "#{model} is named as a default and has no capability row"
    end
  end

  # --- vocabularies -------------------------------------------------------

  def test_vocabulary_lookup_normalises_case_hyphens_and_spaces
    expected = send(:resolve_vocab, :stock, "portra")

    assert_equal expected, send(:resolve_vocab, :stock, "PORTRA")
    assert_equal expected, send(:resolve_vocab, :stock, "  portra  ")
  end

  def test_a_multi_word_term_resolves_however_it_is_typed
    key = VOCABULARIES[:lighting].keys.find { |k| k.include?("_") }
    skip "no multi-word lighting term in this build" unless key

    expected = VOCABULARIES[:lighting][key]
    assert_equal expected, send(:resolve_vocab, :lighting, key.tr("_", "-"))
    assert_equal expected, send(:resolve_vocab, :lighting, key.tr("_", " "))
  end

  def test_an_unset_field_contributes_nothing
    assert_nil send(:resolve_vocab, :stock, nil)
  end

  # Refusing beats guessing: a mistyped stock silently rendering on the default
  # film is the failure that produces a plausible wrong picture.
  def test_an_unknown_term_refuses_rather_than_falling_back
    capture_io { assert_raises(SystemExit) { send(:resolve_vocab, :stock, "kodachrome_that_never_existed") } }
  end

  def test_every_vocabulary_key_is_already_in_normal_form
    VOCABULARIES.each do |field, table|
      table.each_key do |key|
        assert_equal key, key.to_s.strip.downcase.tr("- ", "__"),
                     "#{field}.#{key} can never be reached: lookup normalises the input, not the table"
      end
    end
  end

  def test_no_vocabulary_term_expands_to_nothing
    VOCABULARIES.each do |field, table|
      table.each { |key, phrase| refute_empty phrase.to_s.strip, "#{field}.#{key} expands to nothing" }
    end
  end

  # --- prompt compilation -------------------------------------------------

  def test_the_base_prompt_leads_and_the_vocabularies_follow_in_declared_order
    prompt = send(:compile_prompt, "a woman on a pier", { stock: "portra", lens: VOCABULARIES[:lens].keys.first })

    assert prompt.start_with?("a woman on a pier, ")
    assert_includes prompt, VOCABULARIES[:stock]["portra"]
  end

  def test_unset_fields_leave_no_empty_segments
    prompt = send(:compile_prompt, "a bare prompt", {})

    assert_equal "a bare prompt", prompt
    refute_match(/,\s*,/, prompt)
  end

  # --- negative prompt ----------------------------------------------------

  def test_the_skin_guard_is_on_by_default
    negative = send(:compile_negative_prompt, {})

    assert_includes negative, PLASTIC_SKIN_NEGATIVE
    assert_includes negative, ANTI_BEAUTIFICATION_NEGATIVE
  end

  def test_beautification_can_be_allowed_without_dropping_the_plastic_skin_guard
    negative = send(:compile_negative_prompt, { allow_beautify: true })

    assert_includes negative, PLASTIC_SKIN_NEGATIVE
    refute_includes negative, ANTI_BEAUTIFICATION_NEGATIVE
  end

  def test_an_explicit_negative_replaces_the_defaults_entirely
    assert_equal "just this", send(:compile_negative_prompt, { negative: "just this" })
  end

  def test_opting_out_yields_no_negative_at_all
    assert_nil send(:compile_negative_prompt, { no_negative: true })
  end

  # --- aspect ratio -------------------------------------------------------

  def test_an_explicit_ratio_outranks_every_inference
    assert_equal "9:16", send(:infer_aspect_ratio, "a wide landscape", "9:16", "closeup")
  end

  def test_the_framing_distance_outranks_words_in_the_prompt
    assert_equal "16:9", send(:infer_aspect_ratio, "a portrait of a woman", nil, "establishing")
  end

  def test_the_prompt_is_read_when_nothing_else_says
    assert_equal "4:5", send(:infer_aspect_ratio, "a headshot", nil, nil)
    assert_equal "16:9", send(:infer_aspect_ratio, "a wide panorama", nil, nil)
    assert_equal "1:1", send(:infer_aspect_ratio, "an avatar", nil, nil)
    assert_equal "3:2", send(:infer_aspect_ratio, "a woman on a pier", nil, nil), "editorial default"
  end

  def test_every_distance_term_maps_to_a_ratio
    unmapped = VOCABULARIES[:distance].keys.reject { |k| DISTANCE_ASPECT.key?(k) }
    assert_empty unmapped, "these framings fall through to whatever the prompt happens to say: #{unmapped.inspect}"
  end

  def test_every_declared_ratio_is_well_formed
    DISTANCE_ASPECT.each_value { |ratio| assert_match(/\A\d+:\d+\z/, ratio) }
  end

  # --- batch diversification ---------------------------------------------

  def test_a_single_render_is_not_diversified
    assert_equal "a prompt", send(:diversify, "a prompt", 0, 1)
    assert_nil send(:batch_background, 0, 1)
  end

  def test_a_batch_varies_every_axis_between_neighbours
    a = send(:diversify, "p", 0, 4)
    b = send(:diversify, "p", 1, 4)

    refute_equal a, b
    assert a.start_with?("p, ")
  end

  # Strides that share a factor with their pool size revisit a subset and never
  # reach the rest, so a batch of twelve draws from four wardrobes.
  def test_the_strides_walk_the_whole_pool
    { expression: EXPRESSION_POOL, pose: POSE_POOL,
      wardrobe: WARDROBE_POOL, background: BACKGROUND_POOL }.each do |axis, pool|
      stride = POOL_STRIDES.fetch(axis)
      seen = (0...pool.length).map { |i| (i * stride) % pool.length }.uniq

      assert_equal pool.length, seen.length,
                   "#{axis}: stride #{stride} over #{pool.length} entries only ever reaches #{seen.length}"
    end
  end

  def test_a_batch_the_size_of_the_smallest_pool_repeats_nothing
    size = [EXPRESSION_POOL, POSE_POOL, WARDROBE_POOL, BACKGROUND_POOL].map(&:length).min
    prompts = (0...size).map { |i| send(:diversify, "p", i, size) }

    assert_equal size, prompts.uniq.size
  end

  def test_backgrounds_cycle_with_their_own_stride
    picks = (0...BACKGROUND_POOL.length).map { |i| send(:batch_background, i, 4) }
    assert_equal BACKGROUND_POOL.sort, picks.sort
  end

  # --- request assembly ---------------------------------------------------

  def test_only_keys_the_model_accepts_are_sent
    input = send(:build_input, "a prompt", { model: ULTRA, aspect_ratio: "3:2" },
                 seed: 7, negative_prompt: "no plastic skin")

    assert_equal %w[prompt aspect_ratio output_format safety_tolerance seed raw].sort & input.keys.map(&:to_s).sort,
                 input.keys.map(&:to_s).sort
    refute input.key?(:negative_prompt), "ultra takes no negative prompt; sending one is a 422"
  end

  def test_a_model_without_safety_tolerance_is_not_sent_one
    input = send(:build_input, "a prompt", { model: SCHNELL, aspect_ratio: "3:2" },
                 seed: 7, negative_prompt: nil)

    refute input.key?(:safety_tolerance)
    assert_equal 7, input[:seed]
  end

  def test_numeric_knobs_are_sent_under_the_name_this_model_uses
    input = send(:build_input, "p", { model: DEV, guidance: 3.5, steps: 28 },
                 seed: 1, negative_prompt: nil)

    assert_in_delta 3.5, input[:guidance], 1e-9
    assert_equal 28, input[:num_inference_steps]
  end

  # schnell is a 1-4 step model; the --steps 28 that is right for dev is out of
  # range here, which is why the ceiling is per-model.
  def test_a_knob_outside_this_models_range_refuses
    capture_io do
      assert_raises(SystemExit) do
        send(:build_input, "p", { model: SCHNELL, steps: 28 }, seed: 1, negative_prompt: nil)
      end
    end
  end

  def test_a_knob_this_model_does_not_have_refuses_rather_than_being_dropped
    capture_io do
      assert_raises(SystemExit) do
        send(:build_input, "p", { model: ULTRA, guidance: 3.5 }, seed: 1, negative_prompt: nil)
      end
    end
  end

  def test_an_edit_model_carries_the_source_image_through
    input = send(:build_input, "make it dusk", { model: KONTEXT, image: "/tmp/in.png" },
                 seed: 1, negative_prompt: nil)

    assert_equal "/tmp/in.png", input[:input_image]
  end

  def test_nils_never_reach_the_request
    input = send(:build_input, "p", { model: ULTRA }, seed: nil, negative_prompt: nil)
    refute_includes input.values, nil
  end

  # --- alt text and conflicts ---------------------------------------------

  def test_alt_text_describes_the_picture_without_the_film_stock_jargon
    alt = send(:alt_text_for, "a woman on a pier", { distance: "closeup", stock: "portra" })

    assert_includes alt, "a woman on a pier"
    refute_includes alt, VOCABULARIES[:stock]["portra"],
                    "alt text is for a screen reader, not a shot list"
  end

  def test_alt_text_is_bounded
    alt = send(:alt_text_for, "x" * 500, {})
    assert_operator alt.length, :<=, 240
  end

  def test_alt_text_never_emits_a_dangling_separator
    alt = send(:alt_text_for, "a scene", {}, nil)
    assert_equal "a scene", alt
  end

  def test_every_conflict_rule_names_terms_that_exist
    VOCAB_CONFLICTS.each do |field_a, values_a, field_b, values_b|
      [[field_a, values_a], [field_b, values_b]].each do |field, values|
        unknown = values.reject { |v| VOCABULARIES.fetch(field).key?(v) }
        assert_empty unknown, "#{field} conflict names terms no vocabulary has: #{unknown.inspect}"
      end
    end
  end

  def test_a_conflicting_pair_is_reported
    field_a, values_a, field_b, values_b = VOCAB_CONFLICTS.first
    out, err = capture_io do
      send(:warn_vocab_conflicts, { field_a => values_a.first, field_b => values_b.first })
    end

    assert_empty out
    assert_includes err, "incompatible light"
  end

  def test_a_compatible_pair_is_silent
    _out, err = capture_io { send(:warn_vocab_conflicts, { lighting: "golden_hour" }) }
    assert_empty err
  end

  # The request is assembled from PRODUCIBLE_INPUT_KEYS; a capability row that
  # names a key outside it builds a request this file cannot populate.
  def test_no_model_declares_a_key_the_builder_cannot_produce
    MODEL_CAPABILITIES.each do |model, cap|
      unproducible = cap[:input_keys] - PRODUCIBLE_INPUT_KEYS -
                     [cap[:guidance_key], cap[:steps_key], cap[:negative_prompt_key]].compact
      assert_empty unproducible, "#{model} declares #{unproducible.inspect}, which build_input never sets"
    end
  end

  # preprompt carries its own self-check over all seven vocabularies, the six
  # capability rows and the batch strides. It lived below the CLI guard, so no
  # gate and no test could reach it and its only caller was a subcommand a human
  # had to remember to type. Running it here is what makes it a check.
  def test_the_tools_own_self_check_passes
    assert_empty vocab_problems, "preprompt's vocab-check reports problems"
  end

  # Top-level defs land as private methods on Object, so the `true` is what
  # makes this a question about reachability rather than about visibility.
  def test_only_the_predicate_is_hoisted_above_the_cli_guard
    assert respond_to?(:vocab_problems, true), "the self-check is still unreachable from a test"
    refute respond_to?(:vocab_check, true),
           "the reporter exits the process; it belongs below the guard with the CLI"
  end
  # Replicate fetches input_image / input_images over HTTP, so a local path is
  # resolvable only on the machine that made it — and the API does not fail
  # helpfully on one. It creates the prediction, bills it, and fails inside the
  # model. Nothing uploaded before this was added, so every --image call was
  # sending a path, and a chain's second stage would have been the first thing
  # to hit it.
  def test_a_local_path_is_uploaded_and_a_url_is_left_alone
    uploads = []
    client = Object.new
    client.define_singleton_method(:upload_file) do |path|
      uploads << path
      "https://replicate.delivery/uploaded/#{File.basename(path)}"
    end

    Dir.mktmpdir do |dir|
      local = File.join(dir, "frame.jpg")
      File.write(local, "not really a jpeg")

      assert_equal "https://replicate.delivery/uploaded/frame.jpg",
                   upload_reference(client, local)
      assert_equal [local], uploads, "a local file has to be uploaded exactly once"

      uploads.clear
      remote = "https://example.invalid/already.jpg"
      assert_equal remote, upload_reference(client, remote)
      assert_equal "data:image/png;base64,AAAA", upload_reference(client, "data:image/png;base64,AAAA")
      assert_empty uploads, "a URL or data: URI must not be re-uploaded"
    end
  end

  # --- scenarios ----------------------------------------------------------

  # lora's longest descriptor, so the budget is measured against the subject
  # that spends the most of it.
  DESCRIPTOR = "47 year old Norwegian woman, slender, fine-boned, fair Nordic blonde, west coast Norway"

  def test_a_scenario_is_the_same_sitting_every_time_it_is_asked_for
    assert_equal send(:scenario_sitting, 7), send(:scenario_sitting, 7)
  end

  def test_a_run_of_scenarios_repeats_no_sitting
    scenes = (1..200).map { |n| send(:scenario_sitting, n).except("n", "title") }
    assert_equal scenes.length, scenes.uniq.length
  end

  # Neighbours must differ in the light as well as the place, or a set reads as
  # one sitting in different clothes.
  def test_neighbouring_scenarios_change_the_light_and_the_place
    (1..200).each do |n|
      one = send(:scenario_sitting, n)
      other = send(:scenario_sitting, n + 1)
      refute_equal one["key"], other["key"], "scenarios #{n} and #{n + 1} share a light"
      refute_equal one["scene"], other["scene"]
    end
  end

  def test_no_scenario_asks_a_background_for_a_light_it_cannot_have
    (1..200).each do |n|
      sitting = send(:scenario_sitting, n)
      background = BACKGROUND_POOL.find { |b| sitting["scene"].end_with?(b) }
      refused = BACKGROUND_LIGHT_CONFLICTS.fetch(background, []).map { |light| light.tr("_", " ") }
      refute_includes refused, sitting["key"], "scenario #{n}: #{background} lit by #{sitting['key']}"
    end
  end

  def test_every_scenario_names_a_real_lens_distance_and_stock
    (1..60).each do |n|
      sitting = send(:scenario_sitting, n)
      assert_includes LENS_VOCAB.keys, sitting["lens"]
      assert_includes SUBJECT_DISTANCE_VOCAB.keys, sitting["distance"].delete(" ")
      assert STOCK_VOCAB.values.any? { |d| d.start_with?(sitting["stock"]) }, "no stock is called #{sitting['stock']}"
      refute_includes sitting["stock"], ",", "a sitting names the stock; its look is the grade's business"
    end
  end

  def test_a_composed_scenario_fits_inside_clip
    (1..200).each do |n|
      prompt = send(:sitting_prompt, send(:scenario_sitting, n), trigger: "ragnhild", descriptor: DESCRIPTOR)
      assert_operator send(:approximate_tokens, prompt), :<=, TOKEN_LIMIT, prompt
    end
  end

  def test_the_sitting_prompt_puts_identity_before_scenery_before_equipment
    sitting = { "scene" => "at a window", "key" => "sky", "distance" => "3 m", "lens" => "85mm", "stock" => "Portra 400" }
    assert_equal "t, d, at a window, key light sky, 3 m from camera, 85mm, Portra 400",
                 send(:sitting_prompt, sitting, trigger: "t", descriptor: "d")
  end

  def test_a_conflict_naming_a_background_that_does_not_exist_is_a_problem
    table = BACKGROUND_LIGHT_CONFLICTS.merge("a moon base" => %w[soft])
    assert(send(:scenario_problems, conflicts: table).any? { |line| line.include?("a moon base") })
    assert_empty send(:scenario_problems)
  end
end
