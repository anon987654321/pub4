# frozen_string_literal: true

# Soul / neo-soul / soul-jazz harmony — voicing, validation, beauty scoring,
# and progression transforms for Dilla-style chord beauty.
module DillaHarmony
  PAD_MIDI_MIN = 50.0
  # G5, not E5. At 76 a mid-register 13th sat three semitones above the ceiling,
  # so the whole chord was transposed down an octave to fit -- a 12-semitone lurch
  # in the middle of a progression, which is worse than a bright top voice. 50..79
  # is a Rhodes comp's range and PAD_LOWPASS still shapes the top.
  PAD_MIDI_MAX = 79.0
  # hz values are rounded to 2 dp, so a note's MIDI number lands a hair either
  # side of the integer: D4 measures 61.99998 and E5 measures 76.00003. Every
  # register comparison needs slack, or a boundary note is silently dropped.
  MIDI_TOL = 0.5
  MAX_PAD_VOICES = 5

  VOICING_STYLES = %i[spread quartal drop2 drop3 rootless so_what kenny_barron bill_evans cluster].freeze

  SOUL_PROFILES = %i[
    maj7_minor_cycle fourth_third_sixth_second_turn timeless_authentic minor_iv_loop
    major_lifting slash_ninth_cycle two_chord_hypnosis relative_major_turn minor_turnaround
    warm_minor_arc quartal_west_coast slow_ballad_wash minor_triad_walk neo_soul_pocket neo_soul
    dorian_iv_loop backdoor_resolve iv_borrow_minor electronium_loop electronium_classic
    bvi_bvii_minor ii_v_i_major ii_v_i_minor gospel_bIII flat_seven_lift warm_minor_vamp
    modern_quartal_stack funk_sixteenth_turn church_sus minMaj_color dominant_turn deceptive_turn
    plagal_jazz slash_neo_soul suspended_ballad minor_line_cliche stark_minor_pair piano_soul_turn
    jazz_ballad_waltz turnaround_ii_v modal_safe neo_iv_cycle
    modal_quartal_ladder minor_two_five_chain circle_fifths_descent walking_bass_descent
    lydian_glass_cycle pedal_upper_structures bossa_major9_turn phrygian_gold_arc
    two_chord_luminous mixo_sus_loop common_tone_drift third_cycle_triads
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
    chord.merge(hz:)
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
    return unless defined?(DillaMusicGems) && DillaMusicGems.coltrane?
    symbols = chords.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }
    DillaMusicGems.progression_analysis(symbols)
  end

  def hz_to_midi(hz)
    69.0 + 12.0 * Math.log2(hz / 440.0)
  end

  def midi_to_hz(midi)
    (440.0 * (2.0**((midi - 69.0) / 12.0))).round(2)
  end

  # Move the chord into the pad window AS A UNIT.
  #
  # This folded each note independently (`m += 12 while m < MIN; m -= 12 while
  # m > MAX`), which is the exact failure producer_dna's build_voicing documents
  # and guards against: a rootless spread puts the 9th above MIDI 76, folding it
  # down an octave lands it *under* the third, and a wide Rhodes voicing arrives
  # as a semitone cluster in the low-mid. Measured on the Players transcription
  # before this change: Ebmaj7 voiced D4 Eb4 G4 Bb4 -- the major 7th a semitone
  # below the root, the harshest interval available -- and the returning Cm9
  # voiced Eb3 G3 Bb3 C4, root above the 7th with the 9th gone.
  def clamp_register(midis)
    return midis if midis.empty?

    voiced = midis.sort
    shift = 0.0
    shift += 12.0 while voiced.first + shift < PAD_MIDI_MIN - MIDI_TOL
    while voiced.last + shift > PAD_MIDI_MAX + MIDI_TOL &&
          voiced.first + shift - 12.0 >= PAD_MIDI_MIN - MIDI_TOL
      shift -= 12.0
    end
    voiced = voiced.map { |m| m + shift }
    # Wider than the window even after transposing: thin from the top. A thinner
    # chord is still the same chord; one with its top voice folded under the bass
    # is a different one.
    # Half-semitone tolerance: hz values are rounded to 2 dp, so a note sitting
    # exactly on the ceiling (E5 = 659.25 Hz -> MIDI 76.00003) measured as above
    # it and was thrown away -- which is how G13 lost the thirteenth it is named
    # for while the four tones below it stayed.
    kept = voiced.select { |m| m <= PAD_MIDI_MAX + MIDI_TOL }
    kept.length >= 2 ? kept : voiced.first(2)
  end

  # Spacing that keeps a pad reading as a chord instead of a smear. A minor third
  # is the tightest interval that stays clear below the top octave, and a
  # sustained pad has no business holding a semitone anywhere.
  MUD_CEIL = 64.0

  def min_voice_gap(low)
    low < MUD_CEIL ? 3.0 : 2.0
  end

  # Octave-displace a crowded pair rather than dropping a voice. Every voicing this
  # runs on was built from known chord functions, so moving one an octave keeps all
  # of them present. Try both directions before giving up: raise the upper voice,
  # or if the ceiling is in the way, lower the other one. Raise-or-delete was the
  # only option here, and per-voice octave alignment in the voice-leading step
  # lands two voices a semitone apart often enough that it cost real tones -- Bb13
  # arrived as D4 G4, having lost the seventh with no room above to move it.
  def open_spacing(midis)
    voiced = midis.uniq.sort
    8.times do
      i = voiced.each_cons(2).find_index { |a, b| (b - a) < min_voice_gap(a) }
      break unless i

      up = voiced[i + 1] + 12.0
      down = voiced[i] - 12.0
      if up <= PAD_MIDI_MAX + MIDI_TOL
        voiced[i + 1] = up
      elsif down >= PAD_MIDI_MIN - MIDI_TOL
        voiced[i] = down
      else
        voiced.delete_at(i + 1)
      end
      voiced = voiced.uniq.sort
    end
    voiced
  end

  # Keep the comp in one register.
  #
  # Per-voice octave alignment minimises motion voice by voice, which lets a
  # voicing creep upward chord after chord until the ceiling forces it back down
  # in a single octave drop: measured as a 13-semitone lurch between Fm9 and Bb13
  # in the Players transcription, after the earlier fixes removed the clusters
  # that had been hiding it. Anchoring every chord to the first chord's centre
  # keeps the progression where a player's hands would stay.
  def anchor_register(midis, centre)
    return midis if midis.empty? || centre.nil?

    voiced = midis.sort
    (-2..2).map { |oct| voiced.map { |m| m + oct * 12.0 } }
           .select { |s| s.first >= PAD_MIDI_MIN - MIDI_TOL && s.last <= PAD_MIDI_MAX + MIDI_TOL }
           .min_by { |s| ((s.sum / s.length) - centre).abs } || clamp_register(voiced)
  end

  def register_centre(midis)
    midis.empty? ? nil : midis.sum / midis.length
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
    # A chord with no third is suspended, quartal or a slash upper-structure by
    # construction -- the missing third is the point. The styles below rebuild a
    # voicing from assumed intervals and default a missing third to a MAJOR one,
    # which invents a note the chord does not contain: the E9sus4 written "D/E"
    # came back carrying a G# third and an F# ninth, neither of them in it. That
    # made the first chord of the default progression a different chord from the
    # other five (only the first goes through decorate_chord), which is the lurch
    # heard once per cycle. Leave such chords as written.
    return hz unless ivs.any? { |i| [3, 4].include?(i) }

    third_iv = ivs.find { |i| [3, 4].include?(i) } || 4
    fifth_iv = ivs.find { |i| [7, 6].include?(i) }
    seventh_iv = ivs.find { |i| [10, 11].include?(i) }
    ninth_iv = ivs.find { |i| [2, 14].include?(i) }
    eleventh_iv = ivs.find { |i| i == 5 }

    voiced = case style
             when :so_what, :quartal
               [root, root + 5, root + 10, root + 15].first(MAX_PAD_VOICES)
             when :rootless, :bill_evans, :kenny_barron
               # Subtractive, not generative.
               #
               # These built a shell from assumed intervals -- 3rd, 7th, 9th, 11th,
               # defaulting each one that was missing (`ninth_iv || 14`). On a 13
               # chord that discarded the thirteenth and invented a ninth the chord
               # never had: Bb13 came out Bb D F Ab with a 9th on top, which
               # chord_tones_preserved? then correctly rejected, so the curated
               # pipeline threw the voicing away and reverted to a root-position
               # stack. Half the Players transcription reached the render that way.
               #
               # Rootless means "the bass has the root", so take the root out of
               # what the chord actually contains and leave every other tone alone.
               # A triad has nothing to spare, so it keeps its root.
               shell = midis.length >= 4 ? midis.drop(1) : midis
               # The fifth goes only if there is an extension to keep the chord
               # recognisable without it. Dropping root and fifth from a plain 7th
               # leaves two pitch classes, which chord_tones_preserved? rejects --
               # so Fmaj7 lost its voicing and reverted to a root-position stack.
               if fifth_iv && shell.map { |m| ((m - root) % 12).round }.uniq.length >= 4
                 shell = shell.reject { |m| ((m - root) % 12).round == 7 }
               end
               shell
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
               # Only tones the chord has. The ninth was added whenever the chord
               # had three or more intervals (`if ninth_iv || ivs.length >= 3`,
               # defaulting to 14), so 13ths, 6ths and altered dominants all
               # sprouted a ninth and then failed the chord-tone check.
               spread = [root, root + (fifth_iv || 7)]
               spread << root + third_iv + 12
               spread << root + seventh_iv + 12 if seventh_iv
               spread << root + (ninth_iv == 2 ? 14 : ninth_iv) + 12 if ninth_iv
               spread += ivs.reject { |i| [0, third_iv, fifth_iv, seventh_iv, ninth_iv].include?(i) }
                             .map { |i| root + i + 12 }
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

    clamp_register(open_spacing(voiced)).map { |m| midi_to_hz(m) }.first(MAX_PAD_VOICES)
  end

  def decorate_chord(chord, voicing: :spread, rootless: true)
    hz = apply_voicing(chord[:hz], style: voicing, rootless:)
    { name: chord[:name], hz:, bass_hz: chord[:bass_hz] || chord[:hz].min }
  end

  # The voicing a progression asked for.
  #
  # dilla_reference.yml declares `voicing: rootless` on all four documented
  # transcriptions and HARMONY_PROFILES carries it through, but the curated
  # pipeline hardcoded `rootless: false` and the stream's VOICING rotation was
  # only ever tested for `== :cluster` -- so every Dilla chord played its own root
  # while dilla_chord_bass_hz played it too, and the rotation was inaudible.
  def declared_voicing(cfg)
    raw = DillaLofiMachine.profile_entry(cfg[:track])&.dig(:voicing) || cfg[:voicing]
    style = raw.to_s.downcase.tr("-", "_").to_sym
    VOICING_STYLES.include?(style) ? style : :rootless
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
      # chord_voicing is computed a dozen lines above — drop2 through the
      # development, a contrast voicing at the recapitulation, rootless in
      # breakdowns — and the curated branch then discarded it and kept the
      # written register. Since every one of the 248 catalogue progressions is
      # curated, one voicing shape played through every section of every piece,
      # and nine voicing styles were never heard.
      #
      # The bypass exists to protect artist-verified voicings, which is a real
      # concern, so it stays reachable: CURATED_PHASE_VOICING=0 restores it. But
      # the default now varies, because a progression that voices identically in
      # its breakdown and its recapitulation is not being arranged at all.
      out << if curated && ENV["CURATED_PHASE_VOICING"] == "0"
               preserve_chord_register(ch)
             elsif curated
               # Rootless is for non-curated material, where the engine owns the
               # bass. Curated chords keep their root.
               decorate_chord(ch, voicing: chord_voicing, rootless: false)
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
  def voice_lead_chords_indexed(chords, rootless: false, voicing: :rootless)
    return chords if chords.length <= 1

    # Shape every chord, not just the first. `targets.drop(1)` was the old
    # rootless: it removed the bottom voice of a root-position template stack,
    # which drops the root but leaves the rest of the stack closed and in the
    # order the template happened to list it. apply_voicing builds the shell the
    # style actually names (3rd, 7th, 9th for rootless) from the chord's own
    # intervals, and leaves sus/quartal/slash chords alone.
    shaped = chords.map { |c| decorate_chord(c, voicing:, rootless:) }
    led = [preserve_chord_register(shaped.first)]
    prev = led.first[:hz].map { |h| hz_to_midi(h) }.sort
    centre = register_centre(prev)
    shaped.drop(1).each do |nxt|
      targets = nxt[:hz].map { |h| hz_to_midi(h) }.sort
      # Not `[prev.length, ...].min`: that clamped every chord to the narrowest
      # voicing seen so far, and since targets are sorted ascending it always cut
      # from the top. One rootless 3-voice chord early in a progression therefore
      # deleted the thirteenth from every 13 chord after it -- Bb13 arrived as
      # D F Ab. `prev[vi] || prev.last` below already handles a shorter anchor.
      n_voices = [targets.length, MAX_PAD_VOICES].min
      voiced = n_voices.times.map do |vi|
        target = targets[vi] || targets.last
        anchor = prev[vi] || prev.last
        target + (((anchor - target) / 12.0).round * 12.0)
      end
      voiced = anchor_register(clamp_register(open_spacing(voiced)), centre)
      prev = voiced
      hz = dedupe_by_pitch(voiced).first(MAX_PAD_VOICES).map { |m| midi_to_hz(m) }
      led << { name: nxt[:name], hz:, bass_hz: nxt[:bass_hz] || nxt[:hz].min }
    end
    led
  end

  # Only the first chord was decorated here, so a progression opened with a
  # rootless spread and then played seven root-position template stacks nudged
  # into register -- audibly one good chord followed by a block-chord comp.
  def voice_lead_chords(chords, rootless: false, voicing: :spread)
    return chords if chords.length <= 1

    shaped = chords.map { |c| decorate_chord(c, voicing:, rootless:) }
    led = [shaped.first]
    prev = led.first[:hz].map { |h| hz_to_midi(h) }.sort
    centre = register_centre(prev)
    shaped.drop(1).each do |nxt|
      targets = nxt[:hz].map { |h| hz_to_midi(h) }.sort
      anchors = prev.dup
      voiced = targets.map do |target|
        anchor = anchors.empty? ? target : anchors.min_by { |a| pitch_class_dist(a, target) }
        anchors.delete(anchor) if anchors.length > 1
        target + ((anchor - target) / 12.0).round * 12.0
      end
      voiced = anchor_register(clamp_register(open_spacing(voiced)), centre)
      prev = voiced
      hz = dedupe_by_pitch(voiced).first(MAX_PAD_VOICES).map { |m| midi_to_hz(m) }
      led << { name: nxt[:name], hz:, bass_hz: nxt[:bass_hz] || nxt[:hz].min }
    end
    led
  end

  # Two voices on the same note are a doubled unison, not a chord tone, and the
  # engine was shipping them: of 165 voicings logged to progressions_log.txt, 33
  # carried a duplicated pitch, 27 had fewer than three distinct ones, and 9 were
  # a single pitch class repeated -- G/Bb came out D3 D3 D5, which is the fifth
  # three times with the root and third gone.
  #
  # The dedupe was there and could not catch them. It ran on the *frequencies*,
  # after midi_to_hz, so two voices at 146.83 Hz and 147.06 Hz are distinct
  # floats, survive uniq, and are both D3. They only became equal after
  # nearest_note rounded them for the log, which is why the log showed the
  # problem and the code could not see it.
  #
  # The near-collisions come from the octave-shift arithmetic above:
  # `target + ((anchor - target) / 12.0).round * 12.0`, then open_spacing,
  # clamp_register and anchor_register, each nudging a float. Rounding to the
  # semitone is the level the question is actually asked at -- a chord is a set
  # of pitches, not a set of frequencies.
  def dedupe_by_pitch(midis)
    midis.uniq { |m| m.round }
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

  # A ii-V that is actually a ii and a V, and actually chords.
  #
  # Three things were wrong. Each was built by handing apply_voicing a
  # single-element array, and one frequency has no third, so the guard at the top
  # of apply_voicing returned it untouched: every soul profile's turnaround was
  # two bare notes. The intervals were also swapped against their names -- `-5`
  # is a fourth below, the same pitch class as the fifth above, so "turn_ii" was
  # the dominant and "turn_V" the supertonic, and the pair resolved V-ii instead
  # of ii-V. And the tonic was read as `pads.last[:hz].min`, which stopped being
  # the root the moment the voicings went rootless: the lowest voice of a rootless
  # shell is its third or seventh, so the turnaround was transposed to whatever
  # that happened to be.
  #
  # The name is the reliable source for the root, so ask the chord table what the
  # last chord's root is, and build the two shells from real intervals.
  TURNAROUND_SHELLS = { turn_ii: [0, 3, 7, 10, 14], turn_V: [0, 4, 7, 10, 21] }.freeze

  # The upper structure's root, not the bass. A slash chord's reference voicing
  # starts on its bass note by construction, so Cm9/Bb would read as Bb -- a
  # whole tone off, and the turnaround built a whole tone off with it.
  def chord_root_midi(chord)
    sym = chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "").split("/").first.to_s.strip
    hz_to_midi(DillaLofiMachine.chord_from_symbol(sym)[:hz].min)
  rescue StandardError
    hz_to_midi(chord[:hz].min)
  end

  def turnaround_chord(name, root_midi, voicing:, rootless:)
    hz = TURNAROUND_SHELLS.fetch(name).map { |iv| midi_to_hz(root_midi + iv) }
    decorate_chord({ name: name.to_s, hz: }, voicing:, rootless:)
  end

  def add_turnaround_tags(pads, cfg)
    return pads if pads.empty?
    return pads unless soul_profile?(cfg[:track])
    return pads if pads.length < 4

    tonic = chord_root_midi(pads.last)
    style = declared_voicing(cfg)
    rootless = style != :cluster
    pads + [turnaround_chord(:turn_ii, tonic + 2, voicing: style, rootless:),
            turnaround_chord(:turn_V, tonic + 7, voicing: style, rootless:)]
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
    pads, phases = enrich_progression(pads, cfg, phases:, curated: true)
    style = declared_voicing(cfg)
    pads = voice_lead_chords_indexed(pads, rootless: style != :cluster, voicing: style)
    pads = pads.map do |ch|
      next ch if chord_tones_preserved?(ch)
      sym = ch[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "")
      preserve_chord_register(DillaLofiMachine.chord_from_symbol(sym).merge(name: ch[:name], bass_hz: ch[:bass_hz]))
    rescue StandardError
      ch
    end
    # Bach/Dilla theory runtime (coltrane/head_music when available).
    if defined?(DillaTheoryRuntime)
      pads = DillaTheoryRuntime.refine_progression!(pads, cfg:)
    end
    report_harmony_beauty!(pads, cfg)
    [pads, phases]
  end

  # Theory-grounded scoring (DillaHarmonyScore: voice-leading distance,
  # common-tone retention, contrary motion, root-motion strength -- see that
  # file's header) after theory refinement has already run, so the report
  # reflects what actually got rendered, not the pre-refinement draft.
  # Informational only for now (BEAUTY_REPORT=1 to see it) -- not a gate,
  # since a false-reject here would silently swap out a fine progression for
  # no reason anyone could audit after the fact.
  def report_harmony_beauty!(pads, cfg)
    return unless defined?(DillaHarmonyScore) && ENV["BEAUTY_REPORT"] != "0"

    analysis = DillaHarmonyScore.analyze(pads)
    warn "harmony-beauty: #{cfg[:track]} score=#{analysis[:score]} #{analysis[:breakdown]}"
  rescue StandardError => e
    warn "harmony-beauty: scoring failed (#{e.class}: #{e.message})"
  end

  def beautify_pipeline(pads, cfg, phases: [])
    pads = normalize_chord_pads(pads)
    pads = apply_key_borrow(pads, cfg)
    pads = reharm_every_fourth_loop(pads, cfg)
    pads = insert_backdoor(pads, cfg)
    pads = validate_and_fix(pads)
    pads, phases = enrich_progression(pads, cfg, phases:)
    pads = apply_recap_substitutions(pads, cfg, phases)
    pads = insert_secondary_dominants(pads, cfg)
    pads = voice_lead_chords(pads, rootless: soul_profile?(cfg[:track]), voicing: declared_voicing(cfg))
    pads = bass_voice_lead(pads)
    pads = validate_and_fix(pads)
    pads = add_turnaround_tags(pads, cfg)
    if defined?(DillaTheoryRuntime)
      pads = DillaTheoryRuntime.refine_progression!(pads, cfg:)
    end
    report_harmony_beauty!(pads, cfg)
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
      clash: clash_penalty(chords),
    }
  end
end
