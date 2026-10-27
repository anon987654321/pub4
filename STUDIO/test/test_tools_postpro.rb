# frozen_string_literal: true

require_relative "tools_helper"
ToolTest::Tools.load_tool("postpro/postpro.rb")

# postpro is a film emulation: fourteen stocks, each a row in six parallel
# tables (grain, channel grain scale, reciprocity, push response, H&D curve,
# colour matrix). Nothing checked that a stock had a row in all six, and it
# has not -- four of nine stocks were missing reciprocity rows and fell through
# to a default, which is a real film rendered as a different one.
#
# No image is opened here. Everything under test is table shape and scalar
# arithmetic, so this runs without libvips having anything to do.
class TestPostproFilm < Minitest::Test
  POSTPRO_SOURCE = File.join(ToolTest::ROOT, "postpro", "postpro.rb")
  COLOUR_STOCKS = (STOCKS.keys - %i[tri_x ilford_hp5 ilford_delta3200]).freeze

  def test_render_directory_uses_the_shared_dated_output_contract
    configured = ENV.fetch("POSTPRO_OUTPUT_DIR", "").to_s
    output_dir = Postpro::Constitution::OUTPUT_DIR

    assert_equal Studio::OutputPaths.render_directory, output_dir
    assert_equal File.expand_path(configured), output_dir unless configured.empty?
    assert_match(%r{dilla-renders/\d{4}-\d{2}-\d{2}\z}, output_dir) if configured.empty?
  end

  def test_postpro_daily_logs_and_rotations_are_ignored
    ignore = File.read(File.join(File.dirname(POSTPRO_SOURCE), ".gitignore"))

    assert_match(/^postpro\.log\*$/, ignore,
                 "the daily logger creates postpro.log siblings that must stay out of git")
  end

  def test_generated_output_preserves_existing_media_and_sidecar
    Dir.mktmpdir do |dir|
      input = File.join(dir, "source.jpg")
      output = File.join(dir, "postpro_source_portrait_v1.jpg")
      sidecar = "#{output}.json"
      File.write(input, "source")
      File.write(output, "original media")
      File.write(sidecar, "original sidecar")

      with_postpro_output_dir(dir) do
        error = assert_raises(ArgumentError) do
          Postpro::Constitution.verify_output!(input_path: input, output_path: output)
        end
        assert_match(/constitutional output already exists/, error.message)
        assert_equal "original media", File.read(output)
        assert_equal "original sidecar", File.read(sidecar)
      end
    end
  end

  def test_generated_output_refuses_to_reuse_an_orphaned_sidecar
    Dir.mktmpdir do |dir|
      input = File.join(dir, "source.jpg")
      output = File.join(dir, "postpro_source_portrait_v1.jpg")
      sidecar = "#{output}.json"
      File.write(input, "source")
      File.write(sidecar, "existing provenance")

      with_postpro_output_dir(dir) do
        error = assert_raises(ArgumentError) do
          Postpro::Constitution.verify_output!(input_path: input, output_path: output)
        end
        assert_match(/constitutional output already exists/, error.message)
        refute File.exist?(output)
        assert_equal "existing provenance", File.read(sidecar)
      end
    end
  end

  def test_explicit_output_cannot_replace_the_source_or_its_symlink
    Dir.mktmpdir do |dir|
      input = File.join(dir, "source.jpg")
      alias_path = File.join(dir, "source-alias.jpg")
      File.write(input, "original source")
      File.symlink(input, alias_path)

      error = assert_raises(ArgumentError) do
        Postpro::Constitution.verify_distinct_source!(input_path: input, output_path: input)
      end
      assert_match(/constitutional output would overwrite the source/, error.message)

      error = assert_raises(ArgumentError) do
        Postpro::Constitution.verify_distinct_source!(input_path: input, output_path: alias_path)
      end
      assert_match(/constitutional output would overwrite the source/, error.message)
      assert_equal "original source", File.read(input)
    end
  end

  def test_generated_path_allocator_preserves_earlier_grade_and_provenance
    Dir.mktmpdir do |dir|
      original = File.join(dir, "postpro_source_v1.jpg")
      sidecar = "#{original}.json"
      File.write(original, "earlier grade")

      with_postpro_output_dir(dir) do
        candidate = Postpro::Constitution.available_output_path(original)
        refute_equal original, candidate
        assert_match(/\Apostpro_source_v1_\d{8}T\d{12}Z(?:-\d+)?\.jpg\z/,
                     File.basename(candidate))
        refute File.exist?(candidate)

        File.write("#{candidate}.json", "earlier provenance")
        next_candidate = Postpro::Constitution.available_output_path(candidate)
        refute_equal candidate, next_candidate
        refute File.exist?(next_candidate)

        assert_equal "earlier grade", File.read(original)
        assert_equal "earlier provenance", File.read("#{candidate}.json")
        assert Postpro::Constitution.verify_output!(input_path: original, output_path: next_candidate)
      end
    end
  end

  # --- the tables agree about which films exist ---------------------------

  def test_every_stock_declares_a_speed_and_a_grain_figure
    STOCKS.each do |name, data|
      assert_operator data.fetch(:speed), :>, 0, "#{name} has no box speed"
      assert_operator data.fetch(:grain), :>=, 0, "#{name} has no grain figure"
    end
  end

  def test_every_stock_has_a_channel_grain_row
    missing = STOCKS.keys.reject { |s| GRAIN_CHAN_SCALE.key?(s) }
    assert_empty missing, "these render grain equally on all three layers: #{missing.inspect}"
  end

  def test_every_stock_has_a_reciprocity_row
    missing = STOCKS.keys.reject { |s| RECIPROCITY_SHIFT.key?(s) }
    assert_empty missing, "long exposures on these fall through to another film's shift: #{missing.inspect}"
  end

  def test_every_stock_has_a_push_response_row
    missing = STOCKS.keys.reject { |s| PUSH_RESPONSE.key?(s) }
    assert_empty missing, "pushing these borrows another film's crossover: #{missing.inspect}"
  end

  def test_no_table_names_a_film_that_does_not_exist
    { "GRAIN_CHAN_SCALE" => GRAIN_CHAN_SCALE,
      "RECIPROCITY_SHIFT" => RECIPROCITY_SHIFT,
      "PUSH_RESPONSE" => PUSH_RESPONSE }.each do |label, table|
      orphans = table.keys - STOCKS.keys
      assert_empty orphans, "#{label} carries rows no stock can reach: #{orphans.inspect}"
    end
  end

  # --- the rows are physically sensible -----------------------------------

  def test_channel_grain_rows_are_three_positive_scalars
    GRAIN_CHAN_SCALE.each do |name, scales|
      assert_equal 3, scales.size, "#{name} does not describe R, G and B"
      scales.each { |s| assert_operator s, :>, 0.0, "#{name} mutes a layer's grain entirely" }
    end
  end

  # Silver-halide black and white has one emulsion, so its three channels are
  # the same signal and must not be scaled apart.
  def test_grain_scaling_knots_are_the_boolean_envelope
    model = boolean_envelope_knots(GRAIN_SCALING_KNOTS.size)

    GRAIN_SCALING_KNOTS.each_with_index do |knot, index|
      assert_in_delta model[index], knot, 0.02,
                      "knot #{index} is not Newson coverage #{index}/#{GRAIN_SCALING_KNOTS.size - 1}"
    end
    assert_in_delta 1.0, boolean_envelope_r2(GRAIN_SCALING_KNOTS), 0.01
    assert_operator boolean_envelope_r2([1.0] * GRAIN_SCALING_KNOTS.size), :<, 0.2
  end

  def test_monochrome_stocks_grain_all_three_channels_identically
    %i[tri_x ilford_hp5 ilford_delta3200].each do |name|
      assert_equal [1.0, 1.0, 1.0], GRAIN_CHAN_SCALE.fetch(name),
                   "#{name} is one emulsion; per-channel grain is a colour artefact"
    end
  end

  # Reciprocity failure on tungsten stock goes blue: the blue layer keeps
  # responding as the others fall off. A row where blue is not the largest
  # shift is describing something other than reciprocity.
  def test_reciprocity_shifts_blue_hardest
    RECIPROCITY_SHIFT.each do |name, shift|
      assert_operator shift.fetch(:b), :>, shift.fetch(:r),
                      "#{name}'s reciprocity does not go blue"
      assert_operator shift.fetch(:b), :>, shift.fetch(:g)
    end
  end

  def test_push_response_never_boosts_a_channel_past_unity
    PUSH_RESPONSE.each do |name, response|
      response.each do |channel, value|
        assert_operator value, :>, 0.0, "#{name} #{channel} is not a multiplier"
        assert_operator value, :<=, 1.0, "#{name} #{channel} gains from pushing; pushing costs, it does not give"
      end
    end
  end

  def test_pushing_costs_the_blue_layer_most
    PUSH_RESPONSE.each do |name, response|
      assert_operator response.fetch(:b), :<=, response.fetch(:g),
                      "#{name} loses more green than blue when pushed"
    end
  end

  def test_every_colour_stock_carries_a_full_hd_curve_and_matrix
    COLOUR_STOCKS.each do |name|
      data = STOCKS.fetch(name)
      next unless data[:hd]

      %i[r g b].each do |channel|
        curve = data[:hd].fetch(channel)
        assert_equal 4, curve.size, "#{name} #{channel} is not a four-parameter H&D curve"
      end
      assert_equal 9, data[:matrix].size, "#{name}'s colour matrix is not 3x3" if data[:matrix]
    end
  end

  def test_sublayer_weights_sum_to_one
    STOCKS.each do |name, data|
      layers = data[:sublayers]
      next unless layers

      assert_in_delta 1.0, layers.sum { |l| l.fetch(:weight) }, 1e-6,
                      "#{name}'s emulsion layers do not add up to one emulsion"
      layers.each { |l| assert_operator l.fetch(:grain_scale), :>, 0.0 }
    end
  end

  # --- exposure arithmetic ------------------------------------------------

  def test_effective_iso_is_the_box_speed_when_nothing_is_pushed
    assert_in_delta STOCKS[:kodak_portra][:speed].to_f,
                    send(:preset_effective_iso, { stock: :kodak_portra }), 1e-9
  end

  def test_an_explicit_iso_outranks_the_box_speed
    assert_in_delta 1600.0, send(:preset_effective_iso, { stock: :kodak_portra, iso: 1600 }), 1e-9
  end

  def test_a_push_is_a_doubling_per_stop
    box = STOCKS[:kodak_portra][:speed].to_f
    pushed = send(:preset_effective_iso, { stock: :kodak_portra, fx: ["push_pull"], stops: 2.0 })

    assert_in_delta box * 4.0, pushed, 1e-9
  end

  def test_a_pull_halves_it
    box = STOCKS[:kodak_portra][:speed].to_f
    pulled = send(:preset_effective_iso, { stock: :kodak_portra, fx: ["push_pull"], stops: -1.0 })

    assert_in_delta box / 2.0, pulled, 1e-9
  end

  # A stops figure with no push_pull in the chain is a knob the render never
  # reads; honouring it here would make the two disagree.
  def test_stops_without_the_effect_change_nothing
    assert_in_delta STOCKS[:kodak_portra][:speed].to_f,
                    send(:preset_effective_iso, { stock: :kodak_portra, stops: 3.0 }), 1e-9
  end

  def test_the_push_range_is_clamped_to_what_a_lab_will_do
    huge = send(:preset_effective_iso, { stock: :kodak_portra, fx: ["push_pull"], stops: 99.0 })
    assert_in_delta STOCKS[:kodak_portra][:speed] * (2.0**4.0), huge, 1e-9
  end

  def test_an_unknown_stock_falls_back_to_a_named_film_rather_than_to_zero
    assert_operator send(:preset_effective_iso, { stock: :not_a_film }), :>, 0.0
  end

  # --- halation -----------------------------------------------------------

  def test_every_stock_resolves_a_halation_tint
    STOCKS.each_key do |name|
      tint = send(:halation_tint_for, name)
      assert_kind_of Array, tint, "#{name} has no halation tint"
      assert_equal 3, tint.size
    end
  end

  def test_black_and_white_stocks_share_the_neutral_halation
    assert_equal send(:halation_tint_for, :tri_x), send(:halation_tint_for, :ilford_hp5)
    assert_equal send(:halation_tint_for, :tri_x), send(:halation_tint_for, :ilford_delta3200)
  end

  def test_remjet_free_tungsten_stock_halates_like_vision3
    assert_equal send(:halation_tint_for, :kodak_vision3), send(:halation_tint_for, :cinestill_800t),
                 "cinestill is vision3 with the remjet removed; that is what halation means here"
  end

  # --- transfer functions -------------------------------------------------

  def test_the_srgb_transfer_round_trips
    [0.0, 0.001, 0.04045, 0.1, 0.5, 0.9, 1.0].each do |v|
      # 1e-6, not 1e-9: sRGB's two segments meet at 0.04045 by a rounded
      # constant, so the round trip is exact everywhere except within about
      # 3e-8 of the breakpoint. Tightening past that pins a spec approximation,
      # not this code.
      assert_in_delta v, HD.linear_to_srgb(HD.srgb_to_linear(v)), 1e-6,
                      "the transfer function is not invertible at #{v}"
    end
  end

  def test_the_transfer_is_continuous_across_its_own_breakpoint
    below = HD.srgb_to_linear(0.04045 - 1e-9)
    above = HD.srgb_to_linear(0.04045 + 1e-9)

    assert_in_delta below, above, 1e-6, "the linear and power segments do not meet"
  end

  def test_the_transfer_is_monotonic
    values = (0..100).map { |i| HD.srgb_to_linear(i / 100.0) }
    assert_equal values.sort, values
  end

  def test_the_endpoints_are_exact
    assert_in_delta 0.0, HD.srgb_to_linear(0.0), 1e-12
    assert_in_delta 1.0, HD.srgb_to_linear(1.0), 1e-12
    assert_in_delta 1.0, HD.linear_to_srgb(1.0), 1e-12
  end

  # --- seed ---------------------------------------------------------------

  def test_the_seed_is_a_non_negative_int32
    [0, 1, -1, 2_147_483_646, -99_999_999].each do |offset|
      seed = send(:postpro_seed, offset)
      assert_operator seed, :>=, 0
      assert_operator seed, :<, 2_147_483_647
    end
  end

  def test_the_seed_is_stable_for_a_given_offset
    assert_equal send(:postpro_seed, 7), send(:postpro_seed, 7)
  end

  def test_neighbouring_offsets_do_not_collide
    seeds = (0..16).map { |i| send(:postpro_seed, i) }
    assert_equal seeds.size, seeds.uniq.size
  end

  # --- presets ------------------------------------------------------------

  # The effect inventory must span the complete preset body and stop at
  # its AST method boundary, not at a nested `end` or the next constant.
  def test_effect_inventory_includes_late_preset_case_arms
    source = File.read(POSTPRO_SOURCE)
    implemented = send(:preset_effect_names)
    body = send(:postpro_source_method, source, EFFECT_DISPATCH)

    %w[optical_blur lens_flare cinemascope_bars dilla_console_sum].each do |name|
      assert_includes implemented, name
      assert_includes body, %(when "#{name}")
    end
    refute_includes body, "RANDOM_CHAIN_LENGTH ="
  end

  def test_effect_inventory_ignores_comment_and_string_decoys
    source = <<~'RUBY'
      def preset
        fx = "fixture"
        processed = case fx
        when "optical_blur" then optical_blur(processed)
        # when "comment_decoy" then comment_decoy(processed)
        when "lens_flare" then lens_flare(processed)
        end
        "when \"string_decoy\" then string_decoy(processed)"
      end
    RUBY

    assert_equal %w[lens_flare optical_blur],
                 send(:postpro_case_labels, source, :fx).sort
  end

  def test_h_and_d_curve_checker_reports_bad_channels_without_raising
    valid = STOCKS.fetch(:kodak_portra).fetch(:hd).fetch(:r)
    assert_empty send(:hd_curve_problems, :fixture, :r, valid)

    zero_gamma = valid.dup
    zero_gamma[3] = 0
    problem = send(:hd_curve_problems, :fixture, :r, zero_gamma)
    assert_equal 1, problem.length
    assert_match(/gamma 0 is not positive/, problem.first)

    malformed = send(:hd_curve_problems, :fixture, :r, [nil, 0.9, 0.2, 1.0])
    assert_match(/four finite real numbers/, malformed.first)
    invalid_pivot = send(:hd_curve_problems, :fixture, :r, [0.0, 0.9, 1.5, 1.0])
    assert invalid_pivot.any? { |issue| issue.match?(/pivot 1.5 is outside \(0, 1\)/) }

    invalid_min = send(:hd_curve_problems, :fixture, :r, [-0.1, 0.9, 0.2, 1.0])
    assert invalid_min.any? { |issue| issue.include?("Dmin -0.1 is outside [0, 1]") }
    invalid_max = send(:hd_curve_problems, :fixture, :r, [0.0, 1.1, 0.2, 1.0])
    assert invalid_max.any? { |issue| issue.include?("Dmax 1.1 is outside [0, 1]") }

    assert_empty send(:hd_curve_problems, :fixture, :r, valid),
                 "a malformed channel must not poison the next independent curve check"
  end

  def test_stock_matrix_audit_reports_malformed_data_without_raising
    matrix = STOCKS.fetch(:kodak_portra).fetch(:matrix)
    valid = send(:stock_matrix_audit, :portra, matrix)
    assert_nil valid.fetch(:problem)
    assert_operator valid.fetch(:offset), :>=, 0

    missing = send(:stock_matrix_audit, :portra, nil)
    assert_nil missing.fetch(:problem)
    assert_nil missing.fetch(:offset)

    malformed = send(:stock_matrix_audit, :fixture, [1.0, 0.0])
    assert_match(/must contain nine finite real numbers/, malformed.fetch(:problem))

    nonfinite = [1.0] * 9
    nonfinite[4] = Float::NAN
    assert_match(/must contain nine finite real numbers/,
                 send(:stock_matrix_audit, :fixture, nonfinite).fetch(:problem))
  end

  def test_grain_knot_and_grain_level_audits_keep_malformed_rows_local
    assert_empty send(:grain_knot_problems, :fixture, nil)
    assert_empty send(:grain_knot_problems, :fixture, [0.0, 0.5, 1.0])
    assert_match(/needs at least two knots/,
                 send(:grain_knot_problems, :fixture, [0.5]).first)
    assert_match(/go negative/,
                 send(:grain_knot_problems, :fixture, [-0.1, 0.5]).first)
    assert_match(/finite real numbers/,
                 send(:grain_knot_problems, :fixture, [0.0, Float::INFINITY]).first)

    levels, problems = send(
      :stock_grain_levels,
      { valid: { grain: 2 }, invalid: { grain: "two" }, absent: {} },
      0.5
    )
    assert_in_delta 1.0, levels.fetch(:valid)

    assert_equal 1, problems.length
    assert_match(/grain must be a finite nonnegative number/, problems.first)
    refute problems.any? { |issue| issue.start_with?("valid:") }
  end

  def test_finishing_grain_probe_records_failure_and_keeps_the_checker_alive
    probe = Object.new
    issues = send(:finishing_grain_probe_problems, [:house], probe) do |_image, _name|
      raise IOError, "synthetic finishing failure"
    end

    assert_equal 1, issues.length
    assert_match(/finishing-grain bypass probe raises: IOError: synthetic finishing failure/, issues.first)
    assert_empty send(:finishing_grain_probe_problems, [:house], probe) { |image, _name| image }
    assert_match(/no preset grains in its own chain/, send(:finishing_grain_probe_problems, [], probe) { |image, _name| image }.first)
  end

  def test_source_method_reader_covers_output_dispatch_bodies
    source = File.read(POSTPRO_SOURCE)
    methods = send(:postpro_source_methods, source)
    required_calls = {
      "process_file" => "refuse_failed_family!",
      "run_random" => "process_file(",
      "run_watch" => "grade_watched("
    }

    required_calls.each do |name, call|
      body = methods.fetch(name)
      assert_includes body, call, "#{name} source extraction must include #{call}"
      assert_equal 1, body.lines.count { |line| line.start_with?("def ") },
                   "#{name} source extraction must contain only its own top-level method"
    end
    refute_includes methods.fetch("run_random"), "RANDOM_CHAIN_LENGTH ="
  end

  def test_finishing_grain_reachability_follows_calls_not_comments_or_strings
    source = File.read(POSTPRO_SOURCE)
    methods = send(:postpro_source_methods, source)
    calls = methods.transform_values { |body| send(:postpro_method_calls, body) }

    %w[process_file run_random run_uplift run_one_shot run_watch].each do |name|
      assert send(:postpro_method_reaches?, methods, name, "apply_finishing_grain", calls: calls),
             "#{name} must reach the finishing pass through executable calls"
    end

    fixture = {
      "run_random" => <<~RUBY,
        def run_random
          process_file
        end
      RUBY
      "process_file" => <<~RUBY,
        def process_file
          apply_finishing_grain(image)
        end
      RUBY
      "apply_finishing_grain" => <<~RUBY
        def apply_finishing_grain
          image
        end
      RUBY
    }
    fixture_calls = fixture.transform_values { |body| send(:postpro_method_calls, body) }
    assert send(:postpro_method_reaches?, fixture, "run_random", "apply_finishing_grain", calls: fixture_calls),
           "an actual helper chain must count"

    decoy = {
      "run_random" => <<~RUBY
        def run_random
          # apply_finishing_grain(image)
          "process_file("
        end
      RUBY
    }
    decoy_calls = decoy.transform_values { |body| send(:postpro_method_calls, body) }
    refute send(:postpro_method_reaches?, decoy, "run_random", "apply_finishing_grain", calls: decoy_calls),
           "comments and string literals must not satisfy delivery-path validation"
  end

  def test_preset_effect_key_readers_verify_the_actual_case_arm
    source = File.read(POSTPRO_SOURCE)
    preset_source = send(:postpro_source_method, source, EFFECT_DISPATCH)
    pairs = [
      ["spectral_temp", :temp], ["color_temp", :temp],
      ["print_film", :print_stock], ["push_pull", :stops],
      ["faded_print", :age], ["dye_fade", :age], ["expired_film", :age],
      ["reciprocity_failure", :exposure_secs],
      ["lens_distortion", :k1], ["diffraction_blur", :f_number],
      ["tonemap", :tonemap_ev], ["tonemap", :tonemap],
      ["relight", :azimuth], ["relight", :shape],
      ["vintage_lens", :lens],
      ["cinemascope_bars", :aspect_ratio], ["polaroid_frame", :border_style]
    ]

    pairs.each do |effect, key|
      assert send(:preset_effect_reads_key?, preset_source, effect, key),
             "#{effect} must consume its declared #{key} key"
    end

    disconnected = preset_source.sub("target_kelvin: p[:temp]", "target_kelvin: 6504")
    refute send(:preset_effect_reads_key?, disconnected, "spectral_temp", :temp),
           "a matching effect name must not hide a disconnected temperature value"

    disconnected_lens = preset_source.sub('p.fetch(:lens, "zeiss")', '"cooke"')
    refute send(:preset_effect_reads_key?, disconnected_lens, "vintage_lens", :lens),
           "a matching vintage_lens step must actually read the preset lens"

    unused_decoy = <<~RUBY
      fx = "spectral_temp"
      case fx
      when "spectral_temp" then
        p[:temp]
        spectral_temp(processed, target_kelvin: 6504)
      end
    RUBY
    refute send(:preset_effect_reads_key?, unused_decoy, "spectral_temp", :temp),
           "an unused key read elsewhere in the arm must not configure the effect"

    comment_decoy = <<~RUBY
      fx = "spectral_temp"
      case fx
      when "spectral_temp" then spectral_temp(processed, target_kelvin: 6504) # p[:temp]
      end
    RUBY
    refute send(:preset_effect_reads_key?, comment_decoy, "spectral_temp", :temp),
           "a comment must not satisfy the key-reader contract"

    string_decoy = <<~RUBY
      fx = "spectral_temp"
      case fx
      when "spectral_temp" then spectral_temp(processed, target_kelvin: 6504, annotation: "p[:temp]")
      end
    RUBY
    refute send(:preset_effect_reads_key?, string_decoy, "spectral_temp", :temp),
           "a string literal must not satisfy the key-reader contract"

    multiline = <<~RUBY
      fx = "spectral_temp"
      case fx
      when "spectral_temp" then
        spectral_temp(processed, target_kelvin: p[:temp])
      when "color_temp" then color_temp(processed, p[:temp])
      end
    RUBY
    assert send(:preset_effect_reads_key?, multiline, "spectral_temp", :temp),
           "a key read below the when line still belongs to that effect arm"
    refute send(:preset_effect_reads_key?, multiline, "spectral_temp", :age),
           "a neighbouring effect arm must not lend its key to this one"
  end

  def test_duplicate_effect_labels_are_rejected_and_cannot_supply_unreachable_key_reads
    source = <<~RUBY
      fx = "spectral_temp"
      case fx
      when "spectral_temp" then spectral_temp(processed, target_kelvin: 6504)
      when "spectral_temp" then spectral_temp(processed, target_kelvin: p[:temp])
      end
    RUBY

    assert_equal ["spectral_temp"], send(:postpro_case_label_duplicates, source, :fx)
    refute send(:preset_effect_reads_key?, source, "spectral_temp", :temp),
           "a later duplicate when arm is unreachable and cannot satisfy the contract"

    same_arm = <<~RUBY
      fx = "spectral_temp"
      case fx
      when "spectral_temp", "spectral_temp" then spectral_temp(processed, target_kelvin: p[:temp])
      end
    RUBY
    assert_empty send(:postpro_case_label_duplicates, same_arm, :fx),
                 "repeated alternatives in one when arm do not shadow another arm"

    preset_source = send(:postpro_source_method, File.read(POSTPRO_SOURCE), EFFECT_DISPATCH)
    assert_empty send(:postpro_case_label_duplicates, preset_source, :fx),
                 "the production effect dispatch must not contain unreachable duplicate arms"
  end

  def test_preset_smoke_reports_each_failure_without_skipping_later_presets
    visited = []
    issues = send(:preset_smoke_problems, %i[broken healthy], Object.new) do |_probe, name|
      visited << name
      raise IOError, "synthetic render failure" if name == :broken

      :rendered
    end

    assert_equal %i[broken healthy], visited
    assert_equal 1, issues.length
    assert_match(/preset broken raises on an 8x8 probe/, issues.first)
    refute_match(/healthy/, issues.first)
  end

  def test_malformed_preset_rows_and_key_types_are_reported_locally
    rows, problems = send(:auditable_preset_rows, {
      valid: { fx: %w[grain], stock: :kodak_portra },
      broken: :not_a_preset_table
    })

    assert_equal [:valid], rows.keys
    assert_equal ["broken: preset definition is not a table"], problems

    rows, problems = send(:auditable_preset_rows, [])
    assert_empty rows
    assert_equal ["PRESETS is not a table"], problems

    key_readers = { temp: %w[spectral_temp color_temp] }
    string_key = send(:preset_unregistered_keys, { "temp" => 5200 }, key_readers)
    assert_equal [[:invalid_key_type, "\"temp\""]], string_key
  end

  def test_preset_fields_outside_reader_contract_are_rejected
    key_readers = {
      temp: %w[spectral_temp color_temp],
      lens: %w[vintage_lens]
    }
    base = {
      fx: %w[spectral_temp],
      stock: :kodak_portra,
      intensity: 0.85,
      iso: 400,
      temp: 5200,
      lens: "zeiss"
    }

    assert_empty send(:preset_unregistered_keys, base, key_readers),
                 "base fields, measured ISO and registered effect keys are allowed"
    assert_equal [:mystery_filter],
                 send(:preset_unregistered_keys, base.merge(mystery_filter: 0.25), key_readers),
                 "new preset fields must be rejected until their reader is declared"
  end

  def test_every_preset_names_a_stock_that_exists
    unknown = PRESETS.filter_map { |name, data| [name, data[:stock]] if data[:stock] && !STOCKS.key?(data[:stock]) }
    assert_empty unknown, "these presets render on a film with no rows: #{unknown.inspect}"
  end

  # Presets write `stock:` as a symbol and `lens:` as a string. Every reader
  # calls to_sym, so it works; this normalises the same way rather than
  # pretending the two tables agree about their key type.
  def test_every_preset_names_a_lens_that_exists
    unknown = PRESETS.filter_map do |name, data|
      [name, data[:lens]] if data[:lens] && !LENSES.key?(data[:lens].to_sym)
    end
    assert_empty unknown, "these presets name an undefined lens: #{unknown.inspect}"
  end

  def test_every_declared_lens_is_applied_by_its_preset
    unused = PRESETS.filter_map do |name, data|
      name if data[:lens] && !Array(data[:fx]).include?("vintage_lens")
    end

    assert_empty unused, "these declare a lens but do not apply vintage_lens: #{unused.inspect}"
  end

  def test_every_defined_lens_and_stock_is_reachable_from_some_preset
    used_lenses = PRESETS.values.filter_map { |p| p[:lens]&.to_sym }.uniq
    used_stocks = PRESETS.values.filter_map { |p| p[:stock] }.uniq

    assert_empty LENSES.keys - used_lenses, "a lens no preset selects is a comment with a runtime cost"
    assert_empty STOCKS.keys - used_stocks, "a film stock no preset selects is unreachable"
  end

  # The direction that matters: a `stops:` with no push_pull step is a knob
  # nothing reads. postpro names this defect class itself -- street and noir
  # each declared a push with nothing to push, and tungsten an eight-second
  # exposure with nothing to fail reciprocity over.
  def test_no_preset_sets_an_exposure_knob_no_step_reads
    orphans = PRESETS.select do |_, data|
      data.key?(:stops) && !Array(data[:fx]).include?("push_pull")
    end
    assert_empty orphans.keys, "these set stops: with no push_pull step to read it"
  end

  # postpro carries its own table-and-smoke self-check: reachability of every
  # effect, monotonicity of every H&D curve, and four presets run over an 8x8
  # probe. It returns a problem count and its only caller is a CLI flag, so
  # nothing ran it on a schedule. This does.
  def test_the_tools_own_self_check_passes
    skip "libvips absent on this host" unless defined?(Vips)

    problems = nil
    out, = capture_io { problems = send(:vocab_check) }
    assert_equal 0, problems, "postpro --vocab-check reports problems:\n#{out}"
  end

  # An effect that runs, raises nothing, and changes not a single pixel is this
  # tool's recurring defect: print_film raised into a rescue and was skipped,
  # edge_aware_nr's mask was identically zero so it was a plain blur, and
  # newton_rings sat below 8-bit quantisation. vocab_check reported "0 problems"
  # through all three, because it asks whether an effect is reachable rather
  # than whether it does anything. This asks the second question.
  #
  # The probe is noise plus a hard edge over the full range, so an effect has
  # both detail and contrast to act on. INERT lists the ones known to be
  # no-ops on this probe for an honest reason, so the list itself is the record.
  INERT = {
    newton_rings: "amplitude is below 8-bit quantisation at every intensity it is called with",
    shadow_lift: "a target, not an amount: the probe's blacks already sit at the toe it lifts to",
    double_exposure: "needs a second image; a recipe step without one blends the frame with itself",
  }.freeze

  def test_preset_fails_closed_when_an_effect_has_no_implementation
    skip "libvips absent on this host" unless defined?(Vips)

    owner = Object
    original = owner.const_get(:PRESETS)
    previous_pipeline = $postpro_float_pipeline
    owner.send(:remove_const, :PRESETS)
    owner.const_set(
      :PRESETS,
      original.merge(
        fix_missing_effect_contract: {
          fx: %w[missing_effect_for_contract],
          stock: :kodak_portra,
          intensity: 0.5,
        },
      ).freeze,
    )

    error = assert_raises(ArgumentError) do
      preset(build_probe, :fix_missing_effect_contract)
    end
    assert_match(/fx=missing_effect_for_contract has no implementation/, error.message)
    refute $postpro_float_pipeline, "a failed grade must reset the float pipeline"

    Dir.mktmpdir do |dir|
      input = File.join(dir, "frame.jpg")
      build_probe.write_to_file(input)
      with_postpro_output_dir(dir) do
        error = assert_raises(RuntimeError) do
          process_file(input, 1, :fix_missing_effect_contract)
        end
        assert_match(/all 1\/1 variations failed.*no output was written/, error.message)
        assert_empty Dir[File.join(dir, "postpro_*")], "a failed grade must not leave a partial output"
      end
    end
  ensure
    if owner && original
      owner.send(:remove_const, :PRESETS) if owner.const_defined?(:PRESETS, false)
      owner.const_set(:PRESETS, original)
    end
    $postpro_float_pipeline = previous_pipeline
  end

  def test_every_effect_changes_at_least_one_pixel
    skip "libvips absent on this host" unless defined?(Vips)

    probe = build_probe
    unchanged = RECIPE_ALLOWED.reject { |name| INERT.key?(name.to_sym) }.select do |name|
      out = send(:recipe_step, probe, name, 1.0, { blur: 1.0, curve: 1.0, fringe: 1.0, vignette: 1.0 })
      out.nil? || (out.cast("float") - probe.cast("float")).abs.max.zero?
    rescue StandardError
      false # a raising effect is a different defect; vocab_check owns that
    end

    assert_empty unchanged,
                 "these effects ran and changed nothing on a full-range probe:\n  #{unchanged.join("\n  ")}"
  end

  # Colour, not grey. A monochrome probe makes desaturate, ortho_film,
  # skin_protect and stock_matrix look inert when they are behaving correctly —
  # --- the grain model is a claim, so it is measured -----------------------

  # A flat patch at one tone, and the sigma the grain step lays on it.
  def grain_sigma(stock, iso, value, intensity = 1.0)
    $postpro_seed = 1
    flat = (Vips::Image.black(512, 512) + value).cast("uchar")
    flat = flat.bandjoin([flat, flat]).copy(interpretation: :srgb)
    (grain(flat, iso, stock, intensity).colourspace("b-w").cast("float") -
      flat.colourspace("b-w").cast("float")).deviate
  end

  # STOCKS[:grain] means peak luma sigma in 8-bit levels at mid-grey, or it means
  # nothing. Before the Boolean model it meant nothing: Portra at preset strength
  # laid 0.27 levels on flat grey, and no reading of any constant said so.
  def test_a_stock_grains_at_the_strength_it_declares
    { kodak_portra: 400, tri_x: 400, ilford_delta3200: 3200, fuji_velvia: 50 }.each do |stock, iso|
      declared = STOCKS[stock][:grain] * GRAIN_SIGMA_SCALE
      measured = grain_sigma(stock, iso, 128)
      assert_in_delta declared, measured, declared * 0.15,
                      "#{stock} declares #{declared.round(2)} levels at mid-grey and lays #{measured.round(2)}"
    end
  end

  # The Boolean model's amplitude is sqrt(u(1-u)), not u(1-u). The difference is
  # a highlight carrying 1.7 times less grain than a midtone rather than three.
  def test_grain_follows_the_boolean_amplitude_across_the_curve
    peak = STOCKS[:tri_x][:grain] * GRAIN_SIGMA_SCALE
    [48, 96, 176, 216].each do |value|
      u = value / 255.0
      model = 2 * Math.sqrt(u * (1 - u)) * peak
      assert_in_delta model, grain_sigma(:tri_x, 400, value), model * 0.2,
                      "sRGB #{value} is off the model curve"
    end
  end

  # Crystal size and observer blur are separate parameters. They were one, and
  # the blur sat at half the grain it was filtering at every resolution.
  def test_the_scan_blur_does_not_track_the_crystal
    source = File.read(POSTPRO_SOURCE)
    body = send(:postpro_source_method, source, "grain_field")
    assert body, "grain_field must exist"
    assert_includes body, "gaussblur(GRAIN_SCAN_SIGMA)",
                    "the observer blur must be its own constant, not a multiple of the cell"
    refute_match(/gaussblur\(sp\)/, body)
  end

  # Two passes add in quadrature, and 57 of 61 presets carry their own grain.
  def test_the_finishing_pass_stands_down_for_a_chain_that_grains_itself
    probe = (Vips::Image.black(16, 16) + 128).cast("uchar")
    probe = probe.bandjoin([probe, probe]).copy(interpretation: :srgb)
    assert_equal probe, apply_finishing_grain(probe, :portrait)
    refute_equal probe, apply_finishing_grain(probe, :quality_uplift) if
      PRESETS[:quality_uplift] && !Array(PRESETS[:quality_uplift][:fx]).include?("grain")
  end

  # --- a chain is a process, not a filter menu ----------------------------

  def strengths(chain)
    chain.filter_map { |fx, params| [fx, params] if params.is_a?(Numeric) }
  end

  def leads_of(chain)
    strengths(chain).select { |_, value| value >= RANDOM_LEAD_STRENGTH.first }.map(&:first)
  end

  # Every step joins where some preset already put it beside everything held, so
  # a chain stays inside one family without anyone declaring the families.
  def test_every_step_co_occurs_with_every_other_in_some_preset
    40.times do |seed|
      names = (random_chain(Random.new(seed)).map(&:first) - [RANDOM_ALWAYS] - RANDOM_SHAPES).uniq

      # Only the optional wildcard may disagree with the affinity graph. The
      # generator marks it indirectly, so identify the single highest-conflict
      # effect and verify every remaining pair is supported by a real preset.
      stranger = names.max_by { |fx| (names - [fx]).count { |other| random_affinity[[fx, other].sort].zero? } }

      (names - [stranger]).combination(2) do |a, b|
        assert_operator random_affinity[[a, b].sort], :>, 0,
                        "no preset puts #{a} with #{b}: #{names.inspect}"
      end
    end
  end

  # A chain of one effect and some grain is a wasted render. It happened: the
  # five effects no preset uses have no affinity with anything, so seeding on one
  # dead-ended the walk immediately.
  def test_a_chain_is_never_a_single_effect_and_some_grain
    40.times do |seed|
      chain = random_chain(Random.new(seed))
      assert_operator chain.length, :>=, RANDOM_CHAIN_LENGTH.first,
                      "short chain: #{random_chain_name(chain)}"
    end
  end

  # Nine effects at half strength is mud. One or two carry it.
  def test_one_or_two_steps_carry_the_look_and_the_rest_are_seasoning
    40.times do |seed|
      chain = random_chain(Random.new(seed))
      leads = leads_of(chain)
      assert_includes RANDOM_LEADS, leads.length, "#{leads.length} leads: #{random_chain_name(chain)}"
      support = strengths(chain).reject { |fx, _| leads.include?(fx) }.map(&:last)
      assert(support.all? { |value| value <= RANDOM_LEAD_STRENGTH.first },
             "a supporting step is as loud as a lead: #{random_chain_name(chain)}")
    end
  end

  # Dust at 0.94 is the amateur move in one line, and so is dust five times.
  def test_damage_never_leads_and_never_piles_up
    40.times do |seed|
      chain = random_chain(Random.new(seed))
      assert_empty leads_of(chain) & RANDOM_WEAR, "damage is leading: #{random_chain_name(chain)}"
      assert_empty leads_of(chain) & random_common_spine, "the backbone is leading: #{random_chain_name(chain)}"
      marks = chain.map(&:first) & RANDOM_WEAR
      assert_operator marks.length, :<=, RANDOM_WEAR_CEILING, "#{marks.length} marks: #{marks.inspect}"
    end
  end

  # Five versions of one picture is the other way to waste an afternoon.
  def test_a_run_of_chains_does_not_repeat_itself
    rng = Random.new(31)
    drawn = []
    6.times { drawn << random_chain(rng, avoid: drawn) }
    pairs = drawn.combination(2).map { |a, b| random_similarity(a.map(&:first), b.map(&:first)) }
    assert_operator pairs.max, :<=, 0.5, "two chains out of one run are near neighbours"
    stocks = drawn.map { |chain| chain.last.last["stock"] }
    assert_equal stocks.uniq.length, stocks.length, "a run reused a stock: #{stocks.inspect}"
  end

  # --- light and depth ----------------------------------------------------

  # Built rather than read: the subjects' photographs are private and local, so a
  # probe read from them would measure a different picture on every machine.
  def portrait_probe = build_probe

  def low_frequency(image) = image.colourspace("b-w").cast("float").gaussblur(24.0).deviate
  def high_frequency(image)
    luma = image.colourspace("b-w").cast("float")
    (luma - luma.gaussblur(1.0)).deviate
  end

  # The whole claim of relighting as a grade: the modelling moves and the surface
  # does not, because the correction rides as a ratio on all three channels.
  def test_relight_moves_the_light_and_leaves_the_surface
    source = portrait_probe
    lit = relight(source, 0.8, shape: 1.6)
    assert_operator low_frequency(lit), :>, low_frequency(source) * 1.05,
                    "relight did not deepen the modelling"
    assert_in_delta high_frequency(source), high_frequency(lit), high_frequency(source) * 0.08,
                    "relight moved the texture, which is the one thing it must not"
  end

  def test_relight_swings_the_key_with_azimuth
    source = portrait_probe
    left = relight(source, 0.9, azimuth: 180.0).colourspace("b-w")
    right = relight(source, 0.9, azimuth: 0.0).colourspace("b-w")
    half = source.width / 2
    lean = ->(image) { image.extract_area(0, 0, half, image.height).avg - image.extract_area(half, 0, half, image.height).avg }
    assert_operator lean.call(left), :>, lean.call(right), "the key did not move with the azimuth"
  end

  # Near and far in one frame: sharp noise on the left, the same noise softened
  # on the right, and a ramp top to bottom so both halves carry broad contrast
  # for haze to take away. The uniform probe has detail everywhere, so it gives
  # a depth cue nowhere to go.
  def depth_probe(size = 256)
    half = size / 2
    bands = [110, 140, 95].map.with_index do |mean, i|
      ramp = Vips::Image.xyz(size, size).extract_band(1).linear([80.0 / size], [-40.0])
      noise = Vips::Image.gaussnoise(size, size, mean: mean, sigma: 40, seed: 11 + i) + ramp
      far = noise.gaussblur(6.0).extract_area(half, 0, half, size)
      noise.extract_area(0, 0, half, size).join(far, :horizontal)
    end
    Vips::Image.bandjoin(bands).cast("uchar").copy(interpretation: :srgb)
  end

  # Haze belongs where the detail is not, or it is a global wash wearing the name
  # of a depth cue. On depth_probe the real cue moves the fine detail by half a
  # percent and a wash over the whole frame by forty-four.
  def test_aerial_depth_leaves_the_sharp_parts_alone
    source = depth_probe
    hazed = aerial_depth(source, 1.0)
    assert_in_delta high_frequency(source), high_frequency(hazed), high_frequency(source) * 0.06,
                    "the haze reached the detail"
    assert_operator low_frequency(hazed), :<, low_frequency(source), "nothing receded"
  end

  # Every picture gets one, and it leads.
  def test_every_chain_shapes_the_light
    30.times do |seed|
      chain = random_chain(Random.new(seed))
      shaping = chain.map(&:first) & RANDOM_SHAPES
      assert_equal 1, shaping.length, "#{shaping.length} shape steps: #{random_chain_name(chain)}"
      assert_includes leads_of(chain), shaping.first, "the shape step is not leading"
    end
  end

  # Light is the documented default; heavy is asked for.
  def test_light_mode_is_the_documented_default
    had_value = ENV.key?("POSTPRO_HEAVY")
    value = ENV["POSTPRO_HEAVY"]
    ENV.delete("POSTPRO_HEAVY")

    refute heavy_mode?
  ensure
    had_value ? ENV["POSTPRO_HEAVY"] = value : ENV.delete("POSTPRO_HEAVY")
  end

  def test_the_subtle_lane_stays_subtle_when_heavy_mode_is_disabled
    previous = ENV["POSTPRO_HEAVY"]
    ENV["POSTPRO_HEAVY"] = "0"
    30.times do |seed|
      chain = random_chain(Random.new(seed), lane: :subtle_analog)
      assert_empty chain.map(&:first) & RANDOM_WEAR, "wear without --rough: #{random_chain_name(chain)}"
      assert_operator chain.last.last["intensity"], :<=, 0.65, "grain is loud again"
      assert_operator strengths(chain).map(&:last).max, :<=, RANDOM_LEAD_STRENGTH.last
    end
  ensure
    previous.nil? ? ENV.delete("POSTPRO_HEAVY") : ENV["POSTPRO_HEAVY"] = previous
  end

  # --- halation, tone scale, chains ---------------------------------------

  # Light returns off the base a base-thickness away, so the halo peaks OUTSIDE
  # the highlight. Summing two Gaussians put its maximum at the source instead.
  def test_halation_puts_its_light_in_a_ring
    width = 400
    spot = Vips::Image.gaussmat(width / 12.0, 0.001, separable: false, precision: :float)
    spot = spot.linear([320.0 / spot.max], [0]).embed((width - spot.width) / 2, (width - spot.height) / 2, width, width)
    probe = ((Vips::Image.black(width, width) + 40) + spot).cast("uchar")
    probe = probe.bandjoin([probe, probe]).copy(interpretation: :srgb)
    delta = (halation(probe, 1.0).cast("float") - probe.cast("float")).extract_band(0)
    row = delta.extract_area(width / 2, width / 2, width / 2, 1)
    profile = (0...150).map { |x| row.getpoint(x, 0)[0] }
    # How far the source is still bright enough to halate, measured off the probe
    # rather than guessed, because the answer scales with the probe.
    source = probe.colourspace("b-w").extract_area(width / 2, width / 2, width / 2, 1)
    lit = (0...150).count { |x| source.getpoint(x, 0)[0] > 235 }
    assert_operator profile.index(profile.max), :>, lit,
                    "the halo peaks inside the highlight at #{profile.index(profile.max)} px, source lit to #{lit}"
  end

  # The red layer sits deepest, so the returned light is red-biased on a
  # neutral highlight, never grey.
  def test_halation_returns_more_red_than_blue
    width = 400
    spot = Vips::Image.gaussmat(width / 12.0, 0.001, separable: false, precision: :float)
    spot = spot.linear([320.0 / spot.max], [0]).embed((width - spot.width) / 2, (width - spot.height) / 2, width, width)
    probe = ((Vips::Image.black(width, width) + 40) + spot).cast("uchar")
    probe = probe.bandjoin([probe, probe]).copy(interpretation: :srgb)
    delta = halation(probe, 1.0).cast("float") - probe.cast("float")
    red, _green, blue = delta.bandsplit.map(&:avg)
    assert_operator red, :>, blue * 2, "red #{red.round(3)} should dominate blue #{blue.round(3)}"
  end

  # An S-shaped scale: the toe is flatter than the midtones and the shoulder
  # ends under paper white (Dmax), with every step still ordered.
  def test_film_curve_has_a_toe_and_a_shoulder_ceiling
    inputs = [0, 16, 64, 128, 192, 255]
    out = inputs.map do |value|
      flat = (Vips::Image.black(16, 16) + value).cast("uchar")
      film_curve(flat.bandjoin([flat, flat]).copy(interpretation: :srgb), :kodak_portra, 1.0).colourspace("b-w").avg
    end
    assert_equal out.sort, out, "not monotonic: #{out.inspect}"
    toe = (out[1] - out[0]) / 16.0
    mid = (out[3] - out[2]) / 64.0
    assert_operator toe, :<, mid, "toe #{toe.round(2)} is not flatter than the midtones #{mid.round(2)}"
    assert_operator out.last, :<, 254.0, "white is not capped by Dmax: #{out.last}"
  end

  # Weave, dust and dropout draw from the run seed, so one seed is one picture.
  def test_seeded_analog_effects_repeat_exactly
    ramp = Vips::Image.xyz(96, 64).extract_band(0).linear([2.0], [0]).cast("uchar")
    probe = ramp.bandjoin([ramp, ramp]).copy(interpretation: :srgb)
    previous = $postpro_seed
    $postpro_seed = 1234
    %i[gate_weave dust_and_hair minidv_block_dropout vhs_head_switch_band].each do |effect|
      first = send(effect, probe, 0.8)
      second = send(effect, probe, 0.8)
      assert_equal 0.0, (first.cast("float") - second.cast("float")).abs.max, "#{effect} is not repeatable"
    end
  ensure
    $postpro_seed = previous
  end

  def test_every_tone_curve_is_monotonic_and_lands_mid_grey_somewhere_sane
    %i[aces hable hbd agx aces2].each do |type|
      encoded = [0.02, 0.09, 0.18, 0.4, 1.0, 4.0].map do |scene|
        flat = (Vips::Image.black(16, 16) + scene).cast("float")
        image = flat.bandjoin([flat, flat]).copy(interpretation: :scrgb).colourspace("srgb")
        tonemap(image, type: type, intensity: 1.0).colourspace("b-w").avg
      end
      assert_equal encoded.sort, encoded, "#{type} is not monotonic: #{encoded.inspect}"
      assert_operator encoded[2], :>, 40, "#{type} crushes mid-grey"
      assert_operator encoded[2], :<, 200, "#{type} blows mid-grey"
    end
  end

  # A chain that can repeat an effect has to be an ordered list, because a Hash
  # cannot hold the same key twice.
  def test_a_random_chain_is_ordered_always_grains_and_may_repeat
    seen_duplicate = false
    40.times do |seed|
      chain = random_chain(Random.new(seed))
      assert_kind_of Array, chain
      assert_equal RANDOM_ALWAYS, chain.last.first, "grain must be the last word"
      names = chain.map(&:first)
      assert(names.all? { |fx| RECIPE_ALLOWED.include?(fx) }, "chain names an effect recipe cannot call")
      # Over first occurrences: a second pass of an effect deliberately runs later
      # than its own stage, so it is the process that has to be in order, not the
      # literal sequence.
      ranks = names[0...-1].uniq.map { |fx| random_stage_rank[fx] }
      assert_equal ranks.sort, ranks, "chain is out of stage order: #{names.inspect}"
      seen_duplicate ||= names.tally.any? { |_, count| count > 1 }
    end
    assert seen_duplicate, "forty chains and not one repeated an effect"
  end

  def test_the_toy_filter_pool_is_gone
    source = File.read(POSTPRO_SOURCE)
    %w[grain_basic sepia_basic glitch_basic random_fx].each do |name|
      refute_includes source, "def #{name}", "#{name} survived the collapse into recipe()"
    end
  end

  # they have nothing to act on. Each band gets its own noise field and its own
  # offset, so there is chroma, luminance detail and a hard edge.
  def build_probe
    edge = Vips::Image.black(64, 64).draw_rect([90], 0, 0, 32, 64, fill: true)
    bands = [110, 140, 95].map.with_index do |mean, i|
      ((Vips::Image.gaussnoise(64, 64, mean: mean, sigma: 30, seed: 7 + i) + edge) / 1.4)
    end
    probe = Vips::Image.bandjoin(bands).cast("uchar")
    # A blown highlight, or halation, bokeh_rendering and anamorphic_flare have
    # nothing above threshold to bloom and read as inert when they are not.
    probe.draw_rect([255, 255, 255], 44, 44, 12, 12, fill: true)
         .copy(interpretation: :srgb)
  end

  # --- sidecars ------------------------------------------------------------

  # replicate writes <out>.json with the prompt, model and seed, then grades the
  # same file in place. The grade's record joins that one; it does not erase it.
  def test_a_grade_keeps_the_sidecar_another_tool_wrote
    Dir.mktmpdir do |dir|
      out = File.join(dir, "frame.webp")
      File.write("#{out}.json", JSON.generate("prompt" => "a woman at a window", "model" => "flux", "seed" => 7))
      write_sidecar(out, { schema: "postpro.grade.v1", preset: "portrait" })

      written = JSON.parse(File.read("#{out}.json"))
      assert_equal "a woman at a window", written["prompt"]
      assert_equal 7, written["seed"]
      assert_equal "portrait", written.dig("postpro", "preset")
    end
  end

  def test_a_regrade_replaces_postpros_own_sidecar
    Dir.mktmpdir do |dir|
      out = File.join(dir, "frame.webp")
      write_sidecar(out, { schema: "postpro.grade.v1", preset: "house" })
      write_sidecar(out, { schema: "postpro.grade.v1", preset: "portrait" })

      written = JSON.parse(File.read("#{out}.json"))
      assert_equal "portrait", written["preset"]
      refute written.key?("postpro"), "a regrade nested inside the grade it replaces"
    end
  end

  def test_an_unreadable_sidecar_is_replaced
    Dir.mktmpdir do |dir|
      out = File.join(dir, "frame.webp")
      File.write("#{out}.json", "{ not json")
      write_sidecar(out, { schema: "postpro.grade.v1", preset: "portrait" })

      assert_equal "portrait", JSON.parse(File.read("#{out}.json"))["preset"]
    end
  end
  def probe_file(dir)
    path = File.join(dir, "frame.jpg")
    build_probe.write_to_file(path)
    path
  end

  # process_file writes to the constitution-owned output directory. Tests
  # redirect that single constant into their own temporary directory and put
  # it back even if grading or sidecar creation raises.
  def with_postpro_output_dir(path)
    owner = Postpro::Constitution
    original = owner.const_get(:OUTPUT_DIR)
    owner.send(:remove_const, :OUTPUT_DIR)
    owner.const_set(:OUTPUT_DIR, File.expand_path(path).freeze)
    yield
  ensure
    if owner && defined?(original) && original
      owner.send(:remove_const, :OUTPUT_DIR) if owner.const_defined?(:OUTPUT_DIR, false)
      owner.const_set(:OUTPUT_DIR, original)
    end
  end

  # Every path that writes a graded frame says which grade, from which code, and
  # what it did to the picture. process_file and the watch path wrote none.
  def test_a_graded_frame_records_its_version_and_the_uncanny_readings_either_side
    Dir.mktmpdir do |dir|
      with_postpro_output_dir(dir) do
        input = probe_file(dir)
        assert_equal 1, process_file(input, 1, "portrait")

        out = File.join(dir, "postpro_frame_portrait_v1.jpg")
        assert File.file?(out), "process_file did not write its declared output #{out}"
        sidecar = JSON.parse(File.read("#{out}.json"))
        assert_equal "postpro.grade.v2", sidecar["schema"]
        assert_equal GRADE_VERSION, sidecar["grade_version"]
        assert_match(/\A\h{12}\z/, GRADE_VERSION)
        assert_equal %w[before after], sidecar["uncanny"].keys
        assert_operator sidecar.dig("uncanny", "after", "texture"), :>, 0
      end
    end
  end

  def test_a_watched_arrival_and_an_uplift_stack_both_leave_a_sidecar
    Dir.mktmpdir do |dir|
      input = probe_file(dir)
      watched = File.join(dir, "IMG_1_portrait.jpg")
      grade_watched(input, watched, :portrait)
      assert_equal "portrait", JSON.parse(File.read("#{watched}.json"))["preset"]

      stacked = File.join(dir, "stacked.jpg")
      image = load_image(input)
      processed = rgb_bands(preset_chain(image, %i[portrait noir]))
      processed.write_to_file(stacked)
      write_grade_sidecar(input, stacked, %i[portrait noir], image, processed)
      written = JSON.parse(File.read("#{stacked}.json"))
      assert_equal "portrait+noir", written["preset"]
      assert_equal 2, written["recipe"].length
    end
  end

  def test_stock_sheet_labels_fit_their_cells
    skip "libvips absent on this host" unless defined?(Vips)

    STOCKS.each_key do |stock|
      label = send(:stock_sheet_label, stock, cell: 48)
      assert_operator label.width, :<=, 48, "#{stock} label spills into its neighbour"
      assert_operator label.height, :<=, STOCK_SHEET_LABEL - 4, "#{stock} label leaves its strip"
    end
  end

  # One tile per stock, and the stock actually changes the grade under it.
  def test_the_stock_sheet_grades_one_frame_on_every_stock
    image = build_probe
    # Grain differs between two runs of one stock, so the stock has to move the
    # picture well past that before the swap counts as reaching the chain.
    kodak = rgb_bands(preset(image, :house, stock: :kodak_portra)).cast(:float)
    again = rgb_bands(preset(image, :house, stock: :kodak_portra)).cast(:float)
    tri_x = rgb_bands(preset(image, :house, stock: :tri_x)).cast(:float)
    assert_operator (kodak - tri_x).abs.avg, :>, 3 * (kodak - again).abs.avg,
                    "swapping the stock moved the grade no further than grain does"

    sheet, stocks = stock_sheet(image, :house, cell: 48)
    assert_equal STOCKS.keys, stocks
    columns = Math.sqrt(stocks.length).ceil
    rows = (stocks.length.to_f / columns).ceil
    expected_width = columns * 48 + (columns - 1) * STOCK_SHEET_GAP
    expected_height = rows * (48 + STOCK_SHEET_LABEL) + (rows - 1) * STOCK_SHEET_GAP
    assert_equal expected_width, sheet.width
    assert_equal expected_height, sheet.height
  end

  def test_dilla_analog_translations_are_reachable
    names = %w[dilla_head_bump dilla_tape_saturation dilla_vinyl_bandlimit dilla_phasy dilla_console_sum]
    names.each do |name|
      assert send(:respond_to?, name, true), "Dilla analog effect #{name} is not loaded"
      assert_includes RECIPE_ALLOWED, name, "Dilla analog effect #{name} is not recipe-visible"
    end
    assert_equal %i[dilla_head_bump dilla_vinyl_bandlimit dilla_phasy],
                 DILLA_ANALOG_PRESETS.fetch("vinyl_hot")
    assert_equal %i[dilla_head_bump dilla_phasy],
                 DILLA_ANALOG_PRESETS.fetch("summing_phasy")
  end

  def test_recovered_legacy_postpro_vocabulary_is_reachable
    names = %w[
      film_grain film_halation bloom_effect cross_process golden_hour_glow lomo sepia
      teal_and_orange anamorphic_simulation vhs_degrade color_fade soft_focus double_exposure
      polaroid_frame tape_degradation frame_distortion super8_flicker cinemascope_bars
      halftone_print film_scratches film_stock_emulation sprocket_holes lens_flare glitch
    ]
    names.each { |name| assert send(:respond_to?, name, true), "legacy effect #{name} is not loaded" }

    source = File.read(File.join(File.dirname(POSTPRO_SOURCE), "legacy_effects.rb"))
    names.each { |name| assert_includes source, "def #{name}", "legacy source lost #{name}" }
    assert_equal :kodak_portra, PRESETS.fetch(:legacy_stock_compat)[:stock] if PRESETS.key?(:legacy_stock_compat)
  end

end
