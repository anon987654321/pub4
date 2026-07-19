# frozen_string_literal: true

# Soul / neo-soul / soul-jazz harmony — voicing, validation, beauty scoring,
# and progression transforms for Dilla-style chord beauty.
module DillaHarmony
  SOUL_QUALITIES = %w[maj9 m9 maj7 m7 m11 maj6 6 13 7sus 7alt 7#11 m7b5 sus4].freeze
  PAD_MIDI_MIN = 50.0
  PAD_MIDI_MAX = 76.0
  MAX_PAD_VOICES = 5

  VOICING_STYLES = %i[spread quartal drop2 drop3 rootless so_what kenny_barron bill_evans cluster].freeze

  SOUL_PROFILES = %i[
    maj7_minor_cycle fourth_third_sixth_second_turn timeless_authentic minor_iv_loop
    major_lifting slash_ninth_cycle two_chord_hypnosis relative_major_turn minor_turnaround
    warm_minor_arc quartal_west_coast slow_ballad_wash minor_triad_walk neo_soul_pocket neo_soul
    dorian_iv_loop backdoor_resolve iv_borrow_minor electronium_loop electronium_classic
    bvi_bvii_minor ii_v_i_major ii_v_i_minor gospel_bIII stevie_bVII erykah_minor
    glasper_quartal watermelon_turn church_sus minMaj_color dominant_turn deceptive_turn
    plagal_jazz slash_neo_soul suspended_ballad minor_line_cliche donda_minor keys_woman
    jazz_ballad_waltz turnaround_ii_v modal_safe neo_iv_cycle
    aydin_modal_quartal aydin_jazz_turn bach_circle_descent bach_descending_bass
    lydian_glass_cycle pedal_upper_structures bossa_major9_turn phrygian_gold_arc
    two_chord_luminous mixo_sus_loop common_tone_drift coltrane_lite_triad
    drone_quartal_wash waltz_relative_lift half_time_gospel_plagal double_time_pocket
    whole_tone_bridge upper_triad_tower minor_add9_lullaby dominant_chain_home
  ].freeze

  BLOCKED_GENERATED = %i[polytonal negative_harmony neapolitan chromatic_mediant].freeze

  KEY_BORROW = {
    f_minor: %w[Dbmaj7 Ab Bbm7 Fm7 Fm9 Ebmaj7 Cm7],
    c_major: %w[Am9 Dm9 Fmaj9 G13 Ebmaj7 Bm7],
    d_minor: %w[Am7 Bbmaj7 Cmaj9 Fmaj9 Eb7 Gm7],
    eb_major: %w[Cm9 Fm7 Bb7 Abmaj9 Gm7],
    g_major: %w[Em9 Am9 Cmaj9 D13 Bm7],
    ab_major: %w[Fm7 Bbm7 Ebmaj7 Cm9 Dbmaj7],
  }.freeze

  SUBSTITUTIONS = {
    "m" => "m9", "maj" => "maj9", "7" => "13", "m7" => "m9", "maj7" => "maj9",
    "Fm" => "Fm9", "Ab" => "Abmaj9", "Db" => "Dbmaj7", "Dbmaj7" => "Dbmaj9",
    "Bbm" => "Bbm7", "Cm" => "Cm7", "Dm" => "Dm9", "Gm" => "Gm9", "Am" => "Am9",
    "Cmaj" => "Cmaj9", "Fmaj" => "Fmaj9", "Gmaj" => "Gmaj9", "Ebmaj7" => "Ebmaj9",
  }.freeze

  CONTRAST_VOICINGS = {
    quartal: :drop2, drop2: :rootless, rootless: :spread, cluster: :spread,
    spread: :quartal, drop3: :spread, so_what: :quartal, kenny_barron: :drop2,
    bill_evans: :rootless,
  }.freeze

  @last_progression_chords = nil

  module_function

  def remember_progression(chords)
    @last_progression_chords = chords
  end

  def last_progression_chords
    @last_progression_chords
  end

  def strip_voices(chord, count: 2)
    hz = chord[:hz].sort.last(count)
    chord.merge(hz: hz)
  end

  def chop_tones(chord)
    hz = chord[:hz].sort
    upper = hz.drop(1)
    chord.merge(hz: upper.empty? ? hz : upper)
  end

  def soul_profile?(track)
    sym = DillaLofiMachine.normalize_profile(track)
    SOUL_PROFILES.include?(sym) || DillaLofiMachine.harmony_profile?(sym)
  end

  def progression_insight(chords)
    return nil unless defined?(DillaMusicGems) && DillaMusicGems.coltrane?
    symbols = chords.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }
    DillaMusicGems.progression_analysis(symbols)
  end

  def hz_to_midi(hz)
    69.0 + 12.0 * Math.log2(hz / 440.0)
  end

  def midi_to_hz(midi)
    (440.0 * (2.0**((midi - 69.0) / 12.0))).round(2)
  end

  def clamp_register(midis)
    midis.map do |m|
      m += 12.0 while m < PAD_MIDI_MIN
      m -= 12.0 while m > PAD_MIDI_MAX
      m
    end
  end

  def chord_intervals(hz)
    midis = hz.map { |h| hz_to_midi(h) }.sort
    root = midis.first
    midis.map { |m| ((m - root) % 12).round }.uniq
  end

  def apply_voicing(hz, style:, rootless: true)
    midis = hz.map { |h| hz_to_midi(h) }.sort
    root = midis.first
    ivs = chord_intervals(hz)
    third_iv = ivs.find { |i| [3, 4].include?(i) } || 4
    fifth_iv = ivs.find { |i| [7, 6].include?(i) }
    seventh_iv = ivs.find { |i| [10, 11].include?(i) }
    ninth_iv = ivs.find { |i| [2, 14].include?(i) }
    eleventh_iv = ivs.find { |i| i == 5 }

    voiced = case style
             when :so_what, :quartal
               [root, root + 5, root + 10, root + 15].first(MAX_PAD_VOICES)
             when :rootless, :bill_evans
               pool = [root + third_iv, root + (seventh_iv || 10), root + (ninth_iv || 14)]
               pool << root + (eleventh_iv || 17) if eleventh_iv || style == :bill_evans
               pool << root + third_iv + 12
               pool.uniq.first(MAX_PAD_VOICES)
             when :kenny_barron
               [root + third_iv, root + (seventh_iv || 10), root + (ninth_iv || 14),
                root + (eleventh_iv || 17)].uniq.first(MAX_PAD_VOICES)
             when :drop2
               return hz if midis.length < 4
               ordered = midis.dup
               ordered[-2] -= 12.0 if ordered[-2] > PAD_MIDI_MIN
               ordered
             when :drop3
               return hz if midis.length < 4
               ordered = midis.dup
               ordered[-3] -= 12.0 if ordered[-3] > PAD_MIDI_MIN
               ordered
             when :spread
               spread = [root, root + (fifth_iv || 7)]
               spread << root + third_iv + 12
               spread << root + (seventh_iv || 10) + 12 if seventh_iv
               spread << root + (ninth_iv == 2 ? 14 : (ninth_iv || 14)) + 12 if ninth_iv || ivs.length >= 3
               spread.uniq.first(MAX_PAD_VOICES)
             when :cluster
               [root, root + 1, root + 2, root + 6].first(MAX_PAD_VOICES)
             else
               midis
             end

    voiced = voiced.map(&:to_f)
    if rootless && style != :cluster && %i[spread quartal drop2 drop3].include?(style)
      voiced = voiced.reject { |m| (m - root).abs < 0.5 || ((m - root) % 12).abs < 0.5 && m <= root + 1 }
      voiced = [root + third_iv, root + (seventh_iv || 10) + 12, root + (ninth_iv || 14) + 12] if voiced.length < 3
    end

    clamp_register(voiced.uniq).map { |m| midi_to_hz(m) }.first(MAX_PAD_VOICES)
  end

  def decorate_chord(chord, voicing: :spread, rootless: true)
    hz = apply_voicing(chord[:hz], style: voicing, rootless: rootless)
    { name: chord[:name], hz: hz, bass_hz: chord[:bass_hz] || chord[:hz].min }
  end

  KEY_ALIASES = {
    /f minor/i => :f_minor, /c minor/i => :f_minor, /c# minor/i => :f_minor,
    /d minor/i => :d_minor, /bb/i => :d_minor, /dm/i => :d_minor,
    /c major/i => :c_major, /g major/i => :g_major, /e major/i => :g_major,
    /eb/i => :eb_major, /ab/i => :ab_major
  }.freeze

  def key_sym_for(cfg)
    key = DillaLofiMachine.profile_entry(cfg[:track])&.dig(:key).to_s
    KEY_ALIASES.each { |rx, sym| return sym if key.match?(rx) }
    :f_minor
  end

  def substitute_symbol(sym)
    SUBSTITUTIONS.fetch(sym.to_s, sym.to_s)
  end

  def apply_key_borrow(pads, cfg)
    return pads unless soul_profile?(cfg[:track])
    pool = KEY_BORROW[key_sym_for(cfg)]
    return pads unless pool&.any?
    rng = Random.new(cfg[:track].to_s.hash.abs + pads.length)
    pads.map.with_index do |ch, i|
      next ch unless (i % 8) == 6 && rng.rand < 0.45
      borrowed = pool[rng.rand(pool.length)]
      DillaLofiMachine.chord_from_symbol(borrowed).merge(name: borrowed)
    rescue StandardError
      ch
    end
  end

  def apply_recap_substitutions(pads, cfg, phases)
    return pads unless soul_profile?(cfg[:track])
    pads.map.with_index do |ch, i|
      phase = phases[i]
      next ch unless phase == :recapitulation
      sym = ch[:name].to_s
      sub = substitute_symbol(sym)
      next ch if sub == sym
      DillaLofiMachine.chord_from_symbol(sub).merge(name: sub, bass_hz: ch[:bass_hz])
    rescue StandardError
      ch
    end
  end

  def insert_secondary_dominants(pads, cfg)
    return pads if pads.length < 4 || !soul_profile?(cfg[:track])
    rng = Random.new(cfg[:track].to_s.hash.abs + 99)
    out = pads.dup
    [6, 7].each do |idx|
      next if idx >= out.length
      next unless rng.rand < 0.35
      root = hz_to_midi(out[idx][:hz].min)
      dom = { name: "V7/ii", hz: apply_voicing([midi_to_hz(root + 2)], style: :spread) }
      dom[:hz] = apply_voicing([midi_to_hz(root + 2)], style: :spread)
      out[idx] = dom
    rescue StandardError
      next
    end
    out
  end

  def insert_backdoor(pads, cfg)
    return pads unless soul_profile?(cfg[:track]) && ENV["BACKDOOR"] != "0"
    return pads if pads.length < 8
    idx = 7
    root = hz_to_midi(pads[idx][:hz].min)
    bk = { name: "bVII7", hz: apply_voicing([midi_to_hz(root - 2)], style: :rootless) }
    pads = pads.dup
    pads[idx] = bk
    pads
  end

  def reharm_every_fourth_loop(pads, cfg)
    return pads unless soul_profile?(cfg[:track]) && ENV["REHARM_LOOP"] == "1"
    return pads if pads.length < 4
    rng = Random.new(cfg[:track].to_s.hash.abs)
    pads.map.with_index do |ch, i|
      next ch unless (i % 4) == 3 && rng.rand < 0.4
      sym = ch[:name].to_s
      tritone = sym.sub(/7\z/, "7alt").sub(/maj7/, "7#11")
      DillaLofiMachine.chord_from_symbol(tritone)
    rescue StandardError
      ch
    end
  end

  def pad_overlap_mul(prev, curr)
    return 1.0 unless prev && curr
    motion = root_motion_semitones(prev, curr)
    motion <= 2 ? 1.12 : 1.0
  end

  def stereo_pan_for_voice(voice_i, voices, soul: false)
    return 0.0 unless soul
    spread = 0.28
    (voice_i.to_f / [voices - 1, 1].max - 0.5) * spread * 2.0
  end

  def enrich_progression(pads, cfg, phases: [], curated: false)
    return [pads, phases] if pads.empty?
    soul = soul_profile?(cfg[:track])
    skip_passing = curated || (soul && ENV["SOUL_ENRICH"] != "1")
    use_rootless = !curated && soul

    rng = Random.new((cfg[:track].to_s.hash.abs % 100_000) + pads.length)
    voicing = cfg[:voicing] || :spread
    recap_voicing = CONTRAST_VOICINGS.fetch(voicing, :drop2)
    out = []
    phases_out = []
    pads.each_with_index do |chord, i|
      phase = phases[i]
      chord_voicing = case phase
                      when :recapitulation then recap_voicing
                      when :development
                        if curated
                          voicing == :spread ? :drop2 : voicing
                        else
                          voicing == :spread ? :rootless : voicing
                        end
                      when :breakdown then curated ? voicing : :rootless
                      else voicing
                      end
      sym = chord[:name].to_s
      sym = substitute_symbol(sym) if soul && !curated && phase == :recapitulation && rng.rand < 0.5
      ch = sym != chord[:name].to_s ? (DillaLofiMachine.chord_from_symbol(sym) rescue chord) : chord
      out << if curated
               preserve_chord_register(ch)
             else
               decorate_chord(ch, voicing: chord_voicing, rootless: use_rootless)
             end
      phases_out << phase
      next if skip_passing
      next_chord = pads[(i + 1) % pads.length]
      motion = root_motion_semitones(chord, next_chord)
      passing_rate = curated ? 0.06 : 0.04
      if phase == :development && i < pads.length - 1 && motion <= 4 && rng.rand < passing_rate
        out << passing_cluster(chord, next_chord)
        phases_out << :development
      end
    end
    enriched = out.map.with_index do |c, i|
      phase = phases_out[i]
      shift = phase == :development && (i % 8) == 7 ? 1 : 0
      next c if shift.zero? || c[:name].to_s.start_with?("pass_")
      { name: "#{c[:name]}_t#{shift}", hz: c[:hz].map { |h| (h * (2**(shift / 12.0))).round(2) } }
    end
    [enriched, phases_out.first(enriched.length)]
  end

  def root_motion_semitones(a, b)
    a_root = hz_to_midi(a[:hz].min)
    b_root = hz_to_midi(b[:hz].min)
    diff = (b_root - a_root) % 12
    [diff, 12 - diff].min
  end

  def passing_cluster(a, b)
    a_root = hz_to_midi(a[:hz].min)
    b_root = hz_to_midi(b[:hz].min)
    mid = ((a_root + b_root) / 2.0).round
    cluster = [mid - 1, mid, mid + 1, mid + 4].map { |m| midi_to_hz(m + 12) }
    { name: "pass_#{mid}", hz: cluster.uniq.first(3) }
  end

  def preserve_chord_register(chord)
    hz = clamp_register(chord[:hz].map { |h| hz_to_midi(h) }).map { |m| midi_to_hz(m) }.uniq
    chord.merge(hz: hz.first(MAX_PAD_VOICES))
  end

  def chord_pitch_classes(chord)
    root_pc = hz_to_midi(chord[:hz].min).round % 12
    chord[:hz].map { |h| ((hz_to_midi(h).round - root_pc) % 12) }.uniq.sort
  end

  def expected_pitch_classes(sym)
    ref = DillaLofiMachine.chord_from_symbol(sym.to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, ""))
    chord_pitch_classes(ref)
  rescue StandardError
    []
  end

  def chord_tones_preserved?(chord)
    sym = chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "")
    ref = DillaLofiMachine.chord_from_symbol(sym)
    ref_pcs = ref[:hz].map { |h| hz_to_midi(h).round % 12 }.uniq.sort
    voiced_pcs = chord[:hz].map { |h| hz_to_midi(h).round % 12 }.uniq.sort
    return true if ref_pcs.empty?
    return false unless (voiced_pcs - ref_pcs).empty?
    (voiced_pcs & ref_pcs).length >= [ref_pcs.length - 1, 3].min
  rescue StandardError
    true
  end

  # SATB-style voice leading — bottom voice stays bottom, chord identity intact.
  def voice_lead_chords_indexed(chords, rootless: false)
    return chords if chords.length <= 1
    first_hz = chords.first[:hz].map { |h| hz_to_midi(h) }.sort
    first_hz = first_hz.drop(1) if rootless && first_hz.length > 3
    led = [preserve_chord_register(chords.first.merge(hz: clamp_register(first_hz).map { |m| midi_to_hz(m) }))]
    prev = led.first[:hz].map { |h| hz_to_midi(h) }.sort
    chords.drop(1).each do |nxt|
      targets = nxt[:hz].map { |h| hz_to_midi(h) }.sort
      targets = targets.drop(1) if rootless && targets.length > 3
      n_voices = [prev.length, targets.length, MAX_PAD_VOICES].min
      voiced = n_voices.times.map do |vi|
        target = targets[vi] || targets.last
        anchor = prev[vi] || prev.last
        midi = target + (((anchor - target) / 12.0).round * 12.0)
        midi += 12.0 while midi < PAD_MIDI_MIN
        midi -= 12.0 while midi > PAD_MIDI_MAX
        midi
      end.sort
      prev = voiced
      hz = voiced.map { |m| midi_to_hz(m) }.uniq.first(MAX_PAD_VOICES)
      led << { name: nxt[:name], hz: hz, bass_hz: nxt[:bass_hz] || nxt[:hz].min }
    end
    led
  end

  def voice_lead_chords(chords, rootless: false)
    return chords if chords.length <= 1
    led = [decorate_chord(chords.first, voicing: :spread, rootless: rootless)]
    prev = led.first[:hz].map { |h| hz_to_midi(h) }.sort
    chords.drop(1).each do |nxt|
      targets = nxt[:hz].map { |h| hz_to_midi(h) }.sort
      anchors = prev.dup
      voiced = targets.map do |target|
        anchor = anchors.empty? ? target : anchors.min_by { |a| pitch_class_dist(a, target) }
        anchors.delete(anchor) if anchors.length > 1
        shift = ((anchor - target) / 12.0).round
        midi = target + shift * 12.0
        midi += 12.0 while midi < PAD_MIDI_MIN
        midi -= 12.0 while midi > PAD_MIDI_MAX
        midi
      end.sort
      prev = voiced
      hz = clamp_register(voiced).map { |m| midi_to_hz(m) }.uniq.first(MAX_PAD_VOICES)
      led << { name: nxt[:name], hz: hz, bass_hz: nxt[:bass_hz] || nxt[:hz].min }
    end
    led
  end

  def pitch_class_dist(a, b)
    diff = (a - b) % 12.0
    [diff, 12.0 - diff].min
  end

  def bass_voice_lead(chords)
    return chords if chords.length < 2
    prev_bass = hz_to_midi(chords.first[:bass_hz] || chords.first[:hz].min)
    chords.map.with_index do |ch, i|
      next ch if i.zero?
      target = hz_to_midi(ch[:bass_hz] || ch[:hz].min)
      step = target - prev_bass
      step = step - 12 if step > 7
      step = step + 12 if step < -7
      step = -step.clamp(-5, 5) if ENV["BASS_CONTRARY"] == "1" && step.abs > 4
      bass_midi = prev_bass + step
      bass_midi += 12.0 while bass_midi < 36.0
      bass_midi -= 12.0 while bass_midi > 60.0
      prev_bass = bass_midi
      ch.merge(bass_hz: midi_to_hz(bass_midi))
    end
  end

  def add_turnaround_tags(pads, cfg)
    return pads if pads.empty?
    return pads unless soul_profile?(cfg[:track])
    return pads if pads.length < 4
    last = pads.last
    root = hz_to_midi(last[:hz].min)
    ii = { name: "turn_ii", hz: apply_voicing([midi_to_hz(root - 5)], style: :rootless) }
    v = { name: "turn_V", hz: apply_voicing([midi_to_hz(root + 2)], style: :spread) }
    pads + [ii, v]
  end

  def validate_and_fix(chords)
    return chords if chords.length < 2
    fixed = [chords.first]
    chords.drop(1).each do |ch|
      prev = fixed.last
      clash = mid_register_clash?(prev, ch)
      if clash
        ch = decorate_chord(ch, voicing: :rootless)
        ch = { name: ch[:name], hz: ch[:hz].map { |h| hz_to_midi(h) }.sort.map { |m| midi_to_hz(m + 12) } } if clash
      end
      fixed << ch
    end
    fixed
  end

  def mid_register_clash?(a, b)
    a_midis = a[:hz].map { |h| hz_to_midi(h) }
    b_midis = b[:hz].map { |h| hz_to_midi(h) }
    a_midis.any? do |am|
      b_midis.any? do |bm|
        next false unless am.between?(55, 72) && bm.between?(55, 72)
        (am - bm).abs < 1.2 && pitch_class_dist(am, bm) > 2
      end
    end
  end

  def pedal_probability(cfg)
    return 0.0 if soul_profile?(cfg[:track])
    return 0.0 if DillaLofiMachine::CURATED_PROGRESSIONS.include?(cfg[:progression].to_sym)
    return 0.0 if %i[syncopated_slash_ninth syncopated_slash_alt].include?(cfg[:progression].to_sym)
    0.12
  end

  def chop_density(cfg, section)
    return 0.0 if section == :breakdown
    return 0.15 if soul_profile?(cfg[:track])
    return 0.25 if section == :intro
    0.45
  end

  def pad_sustain_mul(cfg, section, base_rng)
    mul = soul_profile?(cfg[:track]) ? base_rng.rand(0.94..1.08) : base_rng.rand(0.76..1.04)
    mul *= 0.7 if section == :breakdown
    mul *= 1.08 if section == :build && base_rng.rand < 0.5
    mul *= 1.04 if soul_profile?(cfg[:track]) && section == :main
    mul
  end

  def pad_entry_late(cfg, feel, step_p)
    return step_p * 2 + 0.012 if feel == :syncopated_slash_ninth
    return -step_p * 2 if feel == :chromatic_planing
    soul_profile?(cfg[:track]) ? step_p * 0.22 : 0.0
  end

  def score_beauty(chords)
    return 50 if chords.nil? || chords.empty?
    scores = []
    qualities = chords.map { |c| quality_score(c[:name].to_s) }
    scores << (qualities.sum / qualities.length)
    scores << register_score(chords)
    scores << motion_score(chords)
    scores << extension_score(chords)
    scores << clash_penalty(chords)
    raw = scores.sum / scores.length
    raw.clamp(0, 100).round(1)
  end

  def quality_score(name)
    return 85 if name =~ /maj9|m9|maj7|m7|m11|maj6|6|13|sus/i
    return 55 if name =~ /maj|min|m[^a-z]/i
    return 30 if name =~ /pass_|neg_|poly|dim|aug/i
    60
  end

  def register_score(chords)
    ok = chords.count do |c|
      c[:hz].all? { |h| hz_to_midi(h).between?(PAD_MIDI_MIN, PAD_MIDI_MAX) }
    end
    (ok.to_f / chords.length * 100).round
  end

  def motion_score(chords)
    return 80 if chords.length < 2
    motions = chords.each_cons(2).map { |a, b| root_motion_semitones(a, b) }
    smooth = motions.count { |m| m <= 5 }
    (smooth.to_f / motions.length * 100).round
  end

  def extension_score(chords)
    ext = chords.count { |c| c[:hz].length >= 3 }
    (ext.to_f / chords.length * 100).round
  end

  def clash_penalty(chords)
    clashes = chords.each_cons(2).count { |a, b| mid_register_clash?(a, b) }
    [100 - clashes * 15, 0].max
  end

  def normalize_chord_pads(pads)
    pads.map do |c|
      next c if c[:hz]&.any?
      DillaLofiMachine.chord_from_symbol(c[:name])
    rescue StandardError
      c
    end
  end

  # Researched soul loops — voicing + voice-leading only; no random reharm/borrow.
  def beautify_curated_pipeline(pads, cfg, phases: [])
    pads = normalize_chord_pads(pads)
    pads, phases = enrich_progression(pads, cfg, phases: phases, curated: true)
    pads = voice_lead_chords_indexed(pads, rootless: false)
    pads = pads.map do |ch|
      next ch if chord_tones_preserved?(ch)
      sym = ch[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "")
      preserve_chord_register(DillaLofiMachine.chord_from_symbol(sym).merge(name: ch[:name], bass_hz: ch[:bass_hz]))
    rescue StandardError
      ch
    end
    [pads, phases]
  end

  def beautify_pipeline(pads, cfg, phases: [])
    pads = normalize_chord_pads(pads)
    pads = apply_key_borrow(pads, cfg)
    pads = reharm_every_fourth_loop(pads, cfg)
    pads = insert_backdoor(pads, cfg)
    pads = validate_and_fix(pads)
    pads, phases = enrich_progression(pads, cfg, phases: phases)
    pads = apply_recap_substitutions(pads, cfg, phases)
    pads = insert_secondary_dominants(pads, cfg)
    pads = voice_lead_chords(pads, rootless: soul_profile?(cfg[:track]))
    pads = bass_voice_lead(pads)
    pads = validate_and_fix(pads)
    pads = add_turnaround_tags(pads, cfg)
    [pads, phases]
  end

  def fix_chord_for_schedule(chord, prev_chord, curated: false)
    return chord unless prev_chord
    return preserve_chord_register(chord) if curated
    return decorate_chord(chord, voicing: :rootless) if mid_register_clash?(prev_chord, chord)
    chord
  end

  def block_generated?(track, style)
    soul_profile?(track) && BLOCKED_GENERATED.include?(style.to_sym)
  end

  def recommendations(scores)
    recs = []
    recs << "Use maj9/m9/m7 voicings — avoid bare triads and altered clusters." if scores[:extension] < 70
    recs << "Keep pad voices between MIDI 50–76." if scores[:register] < 75
    recs << "Smoother root motion — prefer steps and fourths." if scores[:motion] < 65
    recs << "Mid-register clash between adjacent chords — enable rootless voicings." if scores[:clash] < 80
    recs << "Harmony is soulful — evolve performer/groove next." if recs.empty?
    recs
  end

  def score_breakdown(chords)
    {
      overall: score_beauty(chords),
      extension: extension_score(chords),
      register: register_score(chords),
      motion: motion_score(chords),
      clash: clash_penalty(chords)
    }
  end
end
