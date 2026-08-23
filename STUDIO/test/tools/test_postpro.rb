# frozen_string_literal: true

require_relative "helper"
Studio::Tools.load_tool("postpro/postpro.rb")

# postpro is a film emulation: fourteen stocks, each a row in six parallel
# tables (grain, channel grain scale, reciprocity, push response, H&D curve,
# colour matrix). Nothing checked that a stock had a row in all six, and it
# has not -- four of nine stocks were missing reciprocity rows and fell through
# to a default, which is a real film rendered as a different one.
#
# No image is opened here. Everything under test is table shape and scalar
# arithmetic, so this runs without libvips having anything to do.
class TestPostproFilm < Minitest::Test
  COLOUR_STOCKS = (STOCKS.keys - %i[tri_x ilford_hp5 ilford_delta3200]).freeze

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
    newton_rings: "amplitude is below 8-bit quantisation at every intensity it is called with"
  }.freeze

  def test_every_effect_changes_at_least_one_pixel
    skip "libvips absent on this host" unless defined?(Vips)

    probe = build_probe
    unchanged = RECIPE_ALLOWED.reject { |name| INERT.key?(name.to_sym) }.select do |name|
      adapter = RECIPE_ADAPTERS[name]
      out = if adapter
              adapter.call(probe, 1.0, {})
            elsif respond_to?(name, true)
              send(name, probe, 1.0)
            end
      out.nil? || (out.cast("float") - probe.cast("float")).abs.max.zero?
    rescue StandardError
      false # a raising effect is a different defect; vocab_check owns that
    end

    assert_empty unchanged,
                 "these effects ran and changed nothing on a full-range probe:\n  #{unchanged.join("\n  ")}"
  end

  # Colour, not grey. A monochrome probe makes desaturate, ortho_film,
  # skin_protect and stock_matrix look inert when they are behaving correctly —
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
end
