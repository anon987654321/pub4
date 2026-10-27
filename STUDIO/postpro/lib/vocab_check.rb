# frozen_string_literal: true

def vocab_check
  source = postpro_source
  source_methods = postpro_source_methods(source)
  preset_source = source_methods[EFFECT_DISPATCH]
  implemented = postpro_case_labels(preset_source, :fx)
  problems = []
  valid_presets, malformed_preset_problems = auditable_preset_rows(PRESETS)
  problems.concat(malformed_preset_problems)
  postpro_case_label_duplicates(preset_source, :fx).each do |fx|
    problems << "preset(): duplicate effect arm #{fx.inspect}; later branch is unreachable"
  end

  valid_presets.each do |name, p|
    (Array(p[:fx]) - implemented).each { |fx| problems << "#{name}: fx #{fx.inspect} has no implementation in preset()" }
    problems << "#{name}: stock #{p[:stock].inspect} is not in STOCKS" unless STOCKS.key?(p[:stock])
    if p[:print_stock] && !PRINT_STOCKS.key?(p[:print_stock])
      problems << "#{name}: print_stock #{p[:print_stock].inspect} is not in PRINT_STOCKS"
    end
    if p[:lens]
      unless p[:lens].is_a?(String) || p[:lens].is_a?(Symbol)
        problems << "#{name}: lens #{p[:lens].inspect} must be a name"
      else
        problems << "#{name}: lens #{p[:lens].inspect} is not in LENSES" unless LENSES.key?(p[:lens].to_sym)
      end
    end
    if Array(p[:fx]).include?("vintage_lens") && p[:lens].nil?
      problems << "#{name}: has a vintage_lens step but names no lens, so it gets the zeiss default"
    end
    if Array(p[:fx]).include?("orange_mask") && !C41_STOCKS.include?(p[:stock])
      problems << "#{name}: orange_mask on #{p[:stock]}, which is not a C-41 stock and has no orange mask"
    end
  end

  # A stock reaching an effect whose per-stock table has no row for it does not
  # fail; it quietly becomes a different stock.
  { "GRAIN_CHAN_SCALE" => GRAIN_CHAN_SCALE, "FILM_BASE" => FILM_BASE,
    "PUSH_RESPONSE" => PUSH_RESPONSE, "RECIPROCITY_SHIFT" => RECIPROCITY_SHIFT }.each do |label, table|
    (STOCKS.keys - table.keys).each { |s| problems << "#{s} has no row in #{label}" }
    (table.keys - STOCKS.keys).each { |s| problems << "#{label} has a row for #{s}, which is not in STOCKS" }
  end

  # recipe() grades every step through grade_step, so an allowed effect
  # with no arm there raises instead of grading.
  (RECIPE_ALLOWED - implemented).each do |m|
    problems << "RECIPE_ALLOWED lists #{m}, which has no arm in #{EFFECT_DISPATCH}(), so recipe() raises on it"
  end

  # Reachability. An effect nothing can select is a comment with a runtime cost.
  used = valid_presets.values.flat_map { |p| Array(p[:fx]) }.uniq
  (implemented - used - RECIPE_ALLOWED).each { |fx| problems << "#{fx} is implemented but no preset and no recipe can reach it" }
  (STOCKS.keys - valid_presets.values.map { |p| p[:stock] }.uniq).each { |s| problems << "stock #{s} is defined but no preset uses it" }
  (LENSES.keys - valid_presets.values.filter_map { |p| (p[:lens].to_sym if p[:lens].is_a?(String) || p[:lens].is_a?(Symbol)) }.uniq).each { |l| problems << "lens #{l} is defined but no preset uses it" }
  (PRINT_STOCKS.keys - valid_presets.values.filter_map { |p| p[:print_stock] }.uniq).each { |s| problems << "print stock #{s} is defined but no preset uses it" }

  # A preset key is only honoured if some step in the chain reads it. lens: was
  # the first of these to be found, and it was not the only one -- street and
  # noir each declared a push with nothing to push, and tungsten an eight-second
  # exposure with nothing to fail reciprocity over. Same shape, four keys.
  key_readers = {
    stops: %w[push_pull], age: %w[faded_print dye_fade expired_film],
    print_stock: %w[print_film], exposure_secs: %w[reciprocity_failure],
    k1: %w[lens_distortion], f_number: %w[diffraction_blur], tonemap_ev: %w[tonemap],
    temp: %w[spectral_temp color_temp], tonemap: %w[tonemap],
    lens: %w[vintage_lens], azimuth: %w[relight], shape: %w[relight],
    aspect_ratio: %w[cinemascope_bars], border_style: %w[polaroid_frame],
  }

  # Validate the effect implementation as well as the preset's list. Otherwise
  # a name can remain in the chain while its case arm silently stops reading the
  # very field that made the preset configurable.
  preset_source = source_methods[EFFECT_DISPATCH]
  key_readers.each do |key, readers|
    readers.each do |reader|
      next if preset_effect_reads_key?(preset_source, reader, key)

      problems << "#{reader}: key reader #{key} is listed but preset() does not consume p[:#{key}]"
    end
  end

  valid_presets.each do |name, p|
    preset_unregistered_keys(p, key_readers).each do |key|
      problems << "#{name}: preset key #{key.inspect} has no declared reader contract"
    end
    key_readers.each do |key, readers|
      next unless p.key?(key)
      next unless (Array(p[:fx]) & readers).empty?
      problems << "#{name}: sets #{key}: #{p[key].inspect} but has no #{readers.join('/')} step to read it"
    end
  end

  notes = []

  # A colour matrix whose rows do not sum to 1 shifts neutrals. stock_matrix
  # normalises them at application time so this cannot reach a render, but a
  # row that drifts far from 1 usually means a cast was written into the matrix
  # that belongs in the H&D curve offsets, and that is worth knowing.
  drifting = STOCKS.filter_map do |name, data|
    unless data.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end

    audit = stock_matrix_audit(name, data[:matrix])
    problems << audit[:problem] if audit[:problem]
    [name, audit[:offset]] if audit[:offset] && audit[:offset] > 0.005
  end
  unless drifting.empty?
    notes << "#{drifting.length} stock matrices have rows that do not sum to 1 " \
             "(worst: #{drifting.max_by(&:last).first} at #{(drifting.map(&:last).max * 100).round(1)}%); " \
             "stock_matrix normalises them, but the cast they encode belongs in the H&D offsets"
  end

  # Every H&D curve has to be a curve: monotonic, with the pivot inside the
  # range. A non-monotonic one inverts tones somewhere in the middle.
  STOCKS.merge(PRINT_STOCKS).each do |name, d|
    unless d.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end
    hd = d[:hd]
    next if hd.nil?
    unless hd.is_a?(Hash)
      problems << "#{name}: hd must be a channel table"
      next
    end

    hd.each do |channel, parameters|
      problems.concat(hd_curve_problems(name, channel, parameters))
    end
  end
  STOCKS.each do |name, data|
    unless data.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end
    problems << "#{name} has no speed:, so grain cannot rate it" unless data[:speed]
  end

  # All four output paths finish the same way, or this is two tools wearing one
  # name. Until 2026-08-12 process_file and run_random ran the finishing grain
  # and run_one_shot and run_watch did not, so the same --preset produced a
  # different negative depending on which entry point rendered it — and the thin
  # side of the split was replicate's --postpro handoff, which is the path that
  # makes the finals. Operator's call: all four grain.
  #
  # Read out of this file rather than asserted in prose, because the split had
  # already survived one round of being written down and left alone.
  # Reaching the finishing pass counts, and calling it by name is only one way to
  # reach it: run_random writes through process_file, and asserting on the
  # spelling failed a path whose behaviour was right. A check that measures a
  # spelling measures a spelling.
  calls_by_method = source_methods.transform_values { |body| postpro_method_calls(body) }
  ungrained = %w[process_file run_random run_uplift run_one_shot run_watch].reject do |name|
    postpro_method_reaches?(source_methods, name, "apply_finishing_grain", calls: calls_by_method)
  end
  unless ungrained.empty?
    problems << "output paths disagree on the finishing grain: #{ungrained.join(", ")} " \
                "#{ungrained.one? ? "does" : "do"} not run apply_finishing_grain, the rest do"
  end

  # apply_finishing_grain now stands down for a chain that grains itself, so the
  # standing note about every output being grained twice became a thing to check
  # rather than a thing to report.
  own = valid_presets.select { |_, p| Array(p[:fx]).include?("grain") }
  begin
    probe = Vips::Image.black(8, 8).bandjoin([Vips::Image.black(8, 8)] * 2).copy(interpretation: :srgb) + 128
    problems.concat(finishing_grain_probe_problems(own.keys, probe) do |image, name|
      apply_finishing_grain(image, name)
    end)
  rescue StandardError => e
    problems << "cannot build finishing-grain bypass probe: #{e.class}: #{e.message}"
  end
  notes << "#{own.length} of #{valid_presets.length} valid presets grain in their own chain; " \
           "the rest take the finishing pass"

  # One grain pass, at the end. A lane pool that also draws grain made
  # "grainx2" chains whose passes compounded with the halation drawn before
  # them — the destroyed rather than emulated complaint this tree had to grow
  # out of — so the pools are checked the way every other table is.
  grained_lanes = RANDOM_LANES.select { |_, spec| spec.fetch(:effects).include?(RANDOM_ALWAYS) }
  unless grained_lanes.empty?
    problems << "random lanes draw grain from their pools while the always-grain is appended: " \
                "#{grained_lanes.keys.join(", ")}"
  end

  # The grain model has its own vocabulary now, and the same rule applies to it:
  # a table nothing reads and a name nothing implements both fail quietly.
  problems << "GRAIN_CRYSTAL_FIELD is #{GRAIN_CRYSTAL_FIELD}, which grain_crystals does not build" \
    unless %i[worley perlin].include?(GRAIN_CRYSTAL_FIELD)
  stale = RANDOM_WEAR - RECIPE_ALLOWED
  problems << "RANDOM_WEAR names effects no chain can call: #{stale.join(", ")}" unless stale.empty?
  STOCKS.each do |name, data|
    unless data.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end
    problems.concat(grain_knot_problems(name, data[:grain_knots]))
  end
  quoted, grain_problems = stock_grain_levels(STOCKS, GRAIN_SIGMA_SCALE)
  problems.concat(grain_problems)
  wild = quoted.select { |_, levels| levels < 0.5 || levels > 14.0 }
  problems << "granularity outside anything a scan measures: " \
              "#{wild.map { |n, l| "#{n} at #{l.round(1)} levels" }.join(", ")}" unless wild.empty?
  unless quoted.empty?
    notes << "grain is quoted in 8-bit levels at mid-grey: " \
             "#{quoted.minmax_by { |_, l| l }.map { |n, l| "#{n} #{l.round(1)}" }.join(" to ")}"
  end

  # CONFIG is empty unless a master.json sits beside this file, which is the
  # normal state. Saying so is the difference between a default and a setting
  # nobody can find the reader for.
  unless File.exist?(PostproBootstrap.master_config_path)
    notes << "no #{PostproBootstrap.master_config_path} — CONFIG is empty, so jpeg_quality, variations, " \
             "default_preset and apply_camera_profile_first all take their built-in fallbacks " \
             "(preset=house, and the camera-profile pass is ON: #{CAMERA_PROFILES.values.sum(&:size)} " \
             "bodies across #{CAMERA_PROFILES.size} vendors)"
  end

  # One actual pixel, through actual chains.
  #
  # Everything above reads tables, which is why a frozen memo cache — an error
  # raised in the first or second effect of every preset that has one — sat
  # here undetected while this same function printed "0 problems". A table
  # checker cannot see a runtime failure, so the checker has to run something.
  #
  # 8x8 pixels through four presets chosen to cover the machinery the table
  # checks cannot reach: HD.apply (film_curve), Spectral.adaptation_matrix
  # (spectral_temp), a black-and-white chain and a print chain. Milliseconds.
  smoke = %i[portrait cinematic noir masterpiece].select { |name| valid_presets.key?(name) }
  begin
    probe = Vips::Image.black(8, 8).add(128).cast("uchar").bandjoin([128, 128]).copy(interpretation: :srgb)
    problems.concat(preset_smoke_problems(smoke, probe) { |image, name| preset(image, name) })
  rescue StandardError => e
    problems << "cannot build 8x8 preset probe: #{e.class}: #{e.message}"
  end

  problems.each { |line| puts "BROKEN #{line}" }
  notes.each { |line| puts "NOTE   #{line}" }
  puts "#{PRESETS.length} presets, #{STOCKS.length} stocks, #{LENSES.length} lenses, " \
       "#{implemented.length} effects, #{RECIPE_ALLOWED.length} recipe-allowed — " \
       "#{problems.length} problem(s), #{notes.length} note(s)"
  problems.length
end

def run_introspect
  if ARGV.include?("--vocab-check")
    exit(vocab_check.zero? ? 0 : 1)
  elsif ARGV.include?("--capabilities")
    puts Studio::AnalogCapabilities.report(:postpro)
  elsif ARGV.include?("--list-presets")
    puts list_presets
  elsif ARGV.include?("--list-stocks")
    puts list_stocks
  elsif ARGV.include?("--list-lenses")
    puts list_lenses
  elsif (name = argv_flag("--describe-preset"))
    puts describe_preset(name)
  elsif (scan = argv_flag("--fit-grain"))
    puts fit_grain(scan)
  elsif ARGV.include?("--map")
    puts POSTPRO_SOURCE_FILES.map { |path| Studio::SourceMap.render(path) }.join("\n")
  elsif ARGV.include?("--gallery")
    write_gallery(argv_flag("--gallery") || Dir.pwd)
  elsif (name = argv_flag("--css-filter"))
    puts css_filter(name.to_sym)
  elsif (name = argv_flag("--export-lut"))
    requested_output = argv_flag("--output")
    out = requested_output
    if out.to_s.empty?
      safe_name = name.to_s.gsub(/[^0-9A-Za-z_-]+/, "_")
      out = File.join(Postpro::Constitution::OUTPUT_DIR, "postpro_#{safe_name}.cube")
      out = Postpro::Constitution.available_output_path(out)
      Postpro::Constitution.verify_output!(input_path: POSTPRO_ENTRY, output_path: out)
    else
      Postpro::Constitution.verify_distinct_source!(input_path: POSTPRO_ENTRY, output_path: out)
    end
    size = (argv_flag("--size") || "17").to_i
    export_lut(name.to_sym, out, size)
  end
end
