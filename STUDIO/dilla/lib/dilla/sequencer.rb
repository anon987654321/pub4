# ---------------------------------------------------------------- sequencer
# One groove profile says how the render is played. Everything is in seconds or in
# fractions, all of it scaled by pd_amount (0 is the grid, 1 is the profile, up to 1.5).
#
#   swing         where the second chord of a pair lands (0.5 straight, 0.54 a little late)
#   drum_swing    the same for the off-beat sixteenths, per role: kick, snare, hat
#   offsets       seconds a role sits from the grid: kick, snare, hat, and kick_first
#   pocket        leans in fractions of a sixteenth step, so they follow the tempo: per role
#                 { shift_steps, anchor (steps that lean 0), drift_steps (seeded, per voice and
#                 step in the bar, so every bar leans as the first did) }; a snare off the
#                 backbeat steps takes the ghost entry. A role with no entry keeps its offsets.
#   drunk_amount  0..1, a seeded random nudge on every hit, never past MAX_OFFSET
#   sidechain     { amount, release }: the chords dip on every kick (default: none)
#   texture       { detune, lowpass, reverb }
#   arp, echo     present means on; each overrides the defaults of the same name in the data
class Sequencer
  attr_reader :seed, :pd_amount

  def initialize(data, profile_name:, pd_amount: nil, seed: nil, transpose: 0, wrap: false)
    @data = data
    @transpose = transpose
    @wrap = wrap
    @profile = data['groove_profiles'].fetch(profile_name) { abort "No groove profile: #{profile_name}" }
    @seed = seed || Random.new_seed % 1_000_000
    @pd_amount = (pd_amount || @profile.fetch('pd_amount', 1.0)).to_f.clamp(0.0, 1.5)
  end

  # Unison detune, kept to six cents (a frequency ratio of 0.0035) so the layers stay in tune.
  def detune = [(@profile['texture'] || {}).fetch('detune', 0.0), MAX_DETUNE].min

  # The tempo the profile plays at unless --bpm says otherwise.
  def bpm = @profile.fetch('bpm', 88.0)

  # Chords, each the same length, the odd ones swung late.
  def render_chords(names, bpm, beats, search: true, strum: 0.0)
    beat = 60.0 / bpm
    swing = @profile.fetch('swing', 0.5)
    buf = []
    Chords.freqs(names, search:, transpose: @transpose, wrap: @wrap).each_with_index do |freqs, idx|
      delay = idx.even? ? 0.0 : (swing - 0.5) * beat * @pd_amount
      pad = (delay * SAMPLE_RATE).to_i
      buf.concat(Array.new(pad, 0.0)) if pad > 0
      buf.concat(Synth.chord(freqs, beats * beat, detune: detune, strum:))
    end
    buf
  end

  # The arp settings, or nil when neither a flag nor the profile asks for one. A style names a
  # row of arp.styles (a pattern, a rate in sixteenths, a gate, an octave span); the profile's
  # own keys and then the flags are laid over it.
  def arp_settings(flag, style: nil, rate: nil)
    spec = @profile['arp']
    return nil unless flag || spec || style

    base = (@data['arp'] || {}).reject { |k, _| k == 'styles' }
    name = style || spec&.fetch('style', nil)
    row = name ? (@data.dig('arp', 'styles') || {}).fetch(name) { abort "No arp style: #{name}" } : {}
    settings = base.merge(row).merge((spec || {}).reject { |k, _| k == 'style' })
    settings['style'] = name
    settings['pattern'] = flag if flag.is_a?(String)
    settings['pattern'] ||= settings.fetch('default_pattern')
    settings['rate'] = rate if rate
    abort "No arp pattern: #{settings['pattern']}" unless settings.fetch('patterns').include?(settings['pattern'])
    settings
  end

  # The chord-repeat settings: the whole voicing struck again on the steps of a style from
  # comp.styles. nil unless a flag or the profile asks.
  def comp_settings(flag)
    spec = @profile['repeat']
    return nil unless flag || spec

    base = (@data['comp'] || {}).reject { |k, _| k == 'styles' }
    name = flag.is_a?(String) ? flag : (spec&.fetch('style', nil) || base.fetch('default_style'))
    row = (@data.dig('comp', 'styles') || {}).fetch(name) { abort "No repeat style: #{name}" }
    base.merge(row).merge((spec || {}).reject { |k, _| k == 'style' }).merge('style' => name)
  end

  # The voice that plays the notes: the flag's, else the profile's, else the plain sine stack.
  def voice_spec(flag)
    name = flag || @profile['voice'] || 'sine'
    @data.fetch('voices').fetch(name) { abort "No voice: #{name}" }.merge('name' => name)
  end

  # The Sonitex preset and instance count, or nil when neither a flag nor the profile asks.
  def sonitex_settings(flag, instances: nil)
    spec = @profile['sonitex']
    return nil unless flag || spec

    table = @data.fetch('sonitex')
    name = flag.is_a?(String) ? flag : (spec&.fetch('preset', nil) || table.fetch('default'))
    { 'name' => name, 'preset' => table.fetch('presets').fetch(name) { abort "No sonitex preset: #{name}" },
      'instances' => instances || spec&.fetch('instances', nil) || table.fetch('instances', 1) }
  end

  # The nasty_vcs summing amount, or 0 when off.
  def vcs_amount(flag)
    return flag.to_f if flag.is_a?(Float)

    on = flag || @profile.key?('vcs')
    on ? (@profile['vcs'] || @data.fetch('nasty_vcs').fetch('amount')).to_f : 0.0
  end

  # The colour on the voice bus: Sonitex, then the summing colour.
  def colour(buf, sonitex, vcs)
    buf = Colour.sonitex(buf, sonitex.fetch('preset'), sonitex.fetch('instances'), @seed) if sonitex
    Colour.vcs(buf, vcs)
  end

  # Seconds each voice of a chord waits for the one below it: the flag's milliseconds, the data's when bare.
  def strum(flag)
    return 0.0 unless flag

    (flag == true ? @data.fetch('strum').fetch('ms') : flag) / 1000.0
  end

  # The echo settings with the flags laid over them, or nil when nothing asks for one.
  def echo_settings(flag: nil, mix: nil, feedback: nil, time_ms: nil)
    spec = @profile['echo']
    return nil unless flag || spec

    settings = (@data['echo'] || {}).merge(spec || {})
    settings['heads'] = flag.split(',').map(&:to_i) if flag.is_a?(String)
    abort "No echo heads: #{settings['heads']}" unless settings.fetch('modes').include?(settings['heads'])
    settings['echo_volume'] = mix if mix
    settings['intensity'] = feedback if feedback
    settings['time_ms'] = time_ms if time_ms
    settings
  end

  # The chords one note at a time. Each note starts on its step, late by the profile's swing
  # on the off-beat steps, never moved past MAX_OFFSET; an optional soft pad plays beneath.
  # The notes of every chord as events, before any audio: the arp's one-note steps, or the
  # whole voicing struck on each 'x' of a 16-step pattern. Returns one pluck list per chord.
  def note_events(names, bpm, beats, settings, mode, search: true)
    step = 60.0 / bpm / 4.0
    accent = settings.fetch('accent', [1.0])
    chord_steps = (beats * 4).round
    Chords.midi_notes(names, search:, transpose: @transpose, wrap: @wrap).each_with_index.map do |voices, idx|
      if mode == 'arp'
        rate = settings.fetch('rate', 2).to_f
        pool = Arp.pool(voices, settings.fetch('octaves', 1))
        notes = Arp.sequence(settings.fetch('pattern'), pool, (chord_steps / rate).floor, Zlib.crc32("#{@seed}:#{idx}"))
        plucks = notes.each_with_index.filter_map do |midi, k|
          place((idx * chord_steps) + (k * rate), step, midi, rate * step * settings.fetch('gate', 0.8), accent[k % accent.size]) if midi
        end
        modify(plucks, settings, idx, rate * step, accent.max, pool)
      else
        pattern = settings.fetch('pattern')
        marks = (0...pattern.size).select { |i| pattern[i] == 'x' }
        plucks = []
        (0...chord_steps).step(pattern.size) do |bar|
          marks.each_with_index do |m, j|
            next if bar + m >= chord_steps

            gap = (marks[j + 1] || (pattern.size + marks[0])) - m
            plucks << place((idx * chord_steps) + bar + m, step, voices, gap * step * settings.fetch('gate', 0.5), accent[plucks.size % accent.size])
          end
        end
        modify(plucks, settings, idx, step * 2, accent.max, voices)
      end
    end
  end

  def render_arp(names, bpm, beats, arp, search: true, pad: false, voice: nil)
    buf = Array.new(((((names.size * (beats * 4).round * 60.0 / bpm / 4.0)) + 1.0) * SAMPLE_RATE).to_i, 0.0)
    note_events(names, bpm, beats, arp, 'arp', search:).each { |plucks| sound(buf, plucks, voice || voice_spec(nil)) }
    if pad
      under = render_chords(names, bpm, beats, search:)
      under.each_with_index { |v, i| buf[i] += v * arp.fetch('pad', 0.3) if i < buf.size }
    end
    buf
  end

  # The whole voicing struck again on the steps of a style; a hit lasts the gate share of the
  # distance to the next one.
  def render_repeat(names, bpm, beats, comp, search: true, voice: nil)
    buf = Array.new(((((names.size * (beats * 4).round * 60.0 / bpm / 4.0)) + 1.0) * SAMPLE_RATE).to_i, 0.0)
    note_events(names, bpm, beats, comp, 'repeat', search:).each { |plucks| sound(buf, plucks, voice || voice_spec(nil)) }
    buf
  end

  # A note on its step: the profile's swing leans the off-beat steps late.
  def place(s, step, midi, dur, gain)
    pair = s.round % 4 == 2 ? 2 * step : (s.round.odd? ? step : 0.0)
    Pluck.new(s * step, (@profile.fetch('swing', 0.5) - 0.5) * 2 * pair * @pd_amount, midi, dur, gain)
  end

  def modify(plucks, settings, idx, slot, peak, tones)
    rng = Random.new(Zlib.crc32("#{@seed}:modifiers:#{idx}"))
    settings.fetch('modifiers', []).each do |name|
      plucks = Arp.modify(plucks, name, settings.fetch(name, {}).merge('tones' => tones), rng, slot:, peak:)
    end
    plucks
  end

  # Mix each pluck into the buffer through the voice; a chord's level is shared among its notes.
  def sound(buf, plucks, voice)
    plucks.each do |p|
      notes = Array(p.midi)
      notes.each do |midi|
        samples = Voices.note(voice, midi, p.dur, 0.22 * p.gain / Math.sqrt(notes.size), velocity: p.gain, detune: detune)
        start = [((p.base + p.off.clamp(-MAX_OFFSET, MAX_OFFSET)) * SAMPLE_RATE).to_i, 0].max
        samples.each_with_index { |v, j| buf[start + j] += v if start + j < buf.size }
      end
    end
  end

  # Echo on a buffer, the delay from the settings: milliseconds if given, else a number of beats.
  def echo(buf, settings, bpm, resets: [])
    delay = settings['time_ms'] ? settings['time_ms'] / 1000.0 : settings.fetch('time_beats') * 60.0 / bpm
    out = Echo.process(buf, delay:, heads: settings.fetch('heads'), intensity: settings.fetch('intensity'),
                            volume: settings.fetch('echo_volume'), lowpass: settings['lowpass'],
                            saturation: settings.fetch('saturation', 0.0), reverb: settings.fetch('reverb', 0.0),
                            tail: settings.fetch('tail', 4.0), resets:)
    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |v| v / peak } : out
  end

  # Where every hit lands, in seconds: the 16-step pattern repeats bar after bar until
  # the chords end. Returns [[role, time]], earliest first.
  def drum_hits(pattern_name, bpm, seconds)
    pattern = @data['drum_patterns'].fetch(pattern_name) { abort "No drum pattern: #{pattern_name}" }
    rng = Random.new(@seed)
    step = 60.0 / bpm / 4.0
    offsets = @profile['offsets'] || {}
    pocket = @profile['pocket']
    swings = @profile['drum_swing'] || {}
    drunk = pattern.fetch('drunk', @profile.fetch('drunk_amount', 0.0)).to_f
    hits = []
    first_kick = true
    (seconds / (step * 16)).ceil.times do |bar|
      16.times do |i|
        pattern.each do |role, row|
          next unless row.is_a?(Array) && row[i].to_i.positive?

          nudge = offsets.fetch(role, 0.0)
          nudge = pocket_lean(pocket, role, i) * step if pocket&.key?(role)
          if role == 'kick' && first_kick
            nudge = offsets.fetch('kick_first', nudge) unless pocket&.key?(role)
            first_kick = false
          end
          nudge += (rng.rand * 2 - 1) * MAX_OFFSET * drunk
          # the off-beat eighth (step 2 of 4) and the odd sixteenths take the swing
          pair = i % 4 == 2 ? 2 * step : (i.odd? ? step : 0.0)
          late = (swings.fetch(role, 0.5) - 0.5) * 2 * pair
          # offset, swing and drunk together never move a hit more than MAX_OFFSET
          moved = ((nudge + late) * @pd_amount).clamp(-MAX_OFFSET, MAX_OFFSET)
          t = ((bar * 16 + i) * step) + moved
          hits << [role, [t, 0.0].max] if t < seconds
        end
      end
    end
    hits.sort_by(&:last)
  end

  # How far a hit leans from its step, in sixteenths (before --groove). The draw belongs to
  # the render seed, the voice and the step in the bar, never the bar, so bars repeat.
  def pocket_lean(pocket, role, step_in_bar)
    spec = pocket.fetch(role)
    ghost = pocket['ghost']
    spec = ghost if ghost && role == 'snare' && !pocket.fetch('backbeat', []).include?(step_in_bar)
    return 0.0 if spec.fetch('anchor', []).include?(step_in_bar)

    draw = Random.new(Zlib.crc32("#{@seed}:#{role}:#{step_in_bar}")).rand * 2 - 1
    spec.fetch('shift_steps', 0.0) + spec.fetch('drift_steps', 0.0) * draw
  end

  # The mix levels in dB: the data's, the profile's over them, the flags over those.
  def mix(flags)
    (@data['mix'] || {}).merge(@profile['mix'] || {}).merge(flags || {}).tap do |levels|
      %w[kick snare clap hat perc chords echo].each { |k| levels[k] ||= 0.0 }
    end
  end

  def scale(buf, db)
    gain = 10.0**(db / 20.0)
    buf.map { |v| v * gain }
  end

  # The drums laid over the chords, each role at its mix level; the kick is added after the
  # duck, so the pump never touches it. With a summing colour the drums are a bus of their
  # own and the sum is coloured again; the sum never exceeds full scale.
  def overlay_drums(chord_buf, hits, levels = {}, vcs = 0.0, sonitex: nil, tape: nil)
    drum_bus = (vcs.positive? || sonitex) ? Array.new(chord_buf.size, 0.0) : nil
    out = drum_bus || chord_buf.dup
    hits.each_with_index do |(role, time), hit_index|
      # Re-seed per hit so the transient/noise details vary, not a single cloned sample repeated.
      sample = Drums.new(@seed + ((hit_index + 1) * 104_729)).sounds.fetch(role)
      gain = 0.8 * (10.0**(levels.fetch(role, 0.0) / 20.0))
      variation = case role
                  when 'hat' then [0.68, 0.92, 0.76, 0.84][hit_index % 4]
                  when 'snare' then hit_index.odd? ? 0.92 : 1.0
                  else hit_index.odd? ? 0.94 : 1.0
                  end
      sample.each_with_index do |value, j|
        idx = (time * SAMPLE_RATE).to_i + j
        break if idx >= out.size
        out[idx] += value * gain * variation
      end
    end
    if drum_bus
      drums = if sonitex
                Colour.sonitex(drum_bus, sonitex.fetch('preset'), sonitex.fetch('instances'), @seed + 1)
              else
                drum_bus
              end
      tape_amount = case tape
                    when 'heavy' then 1.0
                    when 'medium' then 0.65
                    when 'light' then 0.35
                    else tape.to_f
                    end
      drums = Colour.tape(drums, amount: tape_amount) if tape_amount.positive?
      drums = Colour.vcs(drums, vcs) if vcs.positive?
      out = chord_buf.each_index.map { |i| chord_buf[i] + drums[i] }
      out = Colour.vcs(out, vcs * 0.5) if vcs.positive?
    end
    peak = out.map(&:abs).max || 0.0
    peak > 1.0 ? out.map { |v| Colour.soft_limit(v) } : out
  end

  # The chords duck on every kick: a gain envelope keyed to the hits, not an oscillator.
  def duck(chord_buf, hits)
    sc = @profile['sidechain'] or return chord_buf
    amount = sc.fetch('amount', 0.0) * @pd_amount
    release = sc.fetch('release', 0.15) * SAMPLE_RATE
    return chord_buf if amount.zero?

    gain = Array.new(chord_buf.size, 1.0)
    hits.each do |role, time|
      next unless role == 'kick'

      start = (time * SAMPLE_RATE).to_i
      (0...(release * 4).to_i).each do |n|
        idx = start + n
        break if idx >= gain.size
        g = 1.0 - amount * Math.exp(-n / release)
        gain[idx] = g if g < gain[idx]
      end
    end
    chord_buf.each_with_index.map { |s, i| s * gain[i] }
  end
end

