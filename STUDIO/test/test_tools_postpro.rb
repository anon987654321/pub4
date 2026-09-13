# frozen_string_literal: true

require_relative "tools_helper"
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
  POSTPRO_SOURCE = File.join(Studio::ROOT, "postpro", "postpro.rb")
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
    body = source[/^def grain_field\b.*?^end$/m]
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
      names = random_chain(Random.new(seed)).map(&:first) - [RANDOM_ALWAYS] - RANDOM_SHAPES
      # The wildcard is the one drawn step allowed to disagree, so drop the worst
      # offender before judging the rest. The shape step is out already: it is
      # appended rather than drawn, because every photograph has light in it.
      stranger = names.max_by { |fx| (names - [fx]).count { |other| random_affinity[[fx, other].sort].zero? } }
      (names - [stranger]).combination(2) do |a, b|
        next if a == b

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

  def portrait_probe
    path = File.join(Studio::ROOT, "lora", "ragnhild", "dataset", "a_photo_of_ragnhild_02.jpg")
    File.file?(path) ? rgb_bands(Vips::Image.new_from_file(path)) : build_probe
  end

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

  # Haze belongs where the detail is not, or it is a global wash wearing the name
  # of a depth cue.
  def test_aerial_depth_leaves_the_sharp_parts_alone
    source = portrait_probe
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

  # Quieter than it was, deliberately, and the wear shelf is out unless asked for.
  def test_the_default_posture_is_subtle
    30.times do |seed|
      chain = random_chain(Random.new(seed))
      assert_empty chain.map(&:first) & RANDOM_WEAR, "wear without --rough: #{random_chain_name(chain)}"
      assert_operator chain.last.last["intensity"], :<=, 0.65, "grain is loud again"
      assert_operator strengths(chain).map(&:last).max, :<=, RANDOM_LEAD_STRENGTH.last
    end
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
end
