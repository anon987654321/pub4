# frozen_string_literal: true

# Bach + J Dilla as Ruby runtime theory — not named “styles”, but operators
# on chord arrays at render time.
#
# Bach (species / thoroughbass practice, simplified for pad voicings):
#   - prefer stepwise upper-voice motion
#   - avoid parallel perfect fifths/octaves between outer voices
#   - contrary motion when bass leaps
#   - circle-of-fifths bias for functional chains
#
# Dilla (neo-soul / MPC harmony practice):
#   - common-tone retention between chords
#   - slash / pedal bass color without reharmonizing the upper structure away
#   - delayed resolution (keep tension tones an extra beat’s worth of voicing)
#   - rootless upper structures when density allows
#
# Uses major_third_cycle_full / head_music when present (DillaMusicGems); otherwise pure math.
module DillaTheoryRuntime
  module_function

  def enabled?
    ENV.fetch("THEORY_RUNTIME", "1") != "0"
  end

  def bach_mode?
    ENV["THEORY_BACH"] == "1" ||
      ENV["TRACK"].to_s.match?(/bach|baroque|circle|fugue/i) ||
      ENV["VOICING"].to_s == "drop2"
  end

  def dilla_mode?
    ENV.fetch("THEORY_DILLA", "1") != "0"
  end

  # Main entry — mutate a progression of {name:, hz:} chords.
  def refine_progression!(chords, cfg: {})
    return chords unless enabled? && chords.is_a?(Array) && chords.length >= 2

    out = chords.map { |c| c.is_a?(Hash) ? c.dup : c }
    out = dilla_common_tone_lock!(out) if dilla_mode?
    out = dilla_slash_pedal_bias!(out, cfg) if dilla_mode?
    out = bach_voice_lead!(out) if bach_mode? || ENV["THEORY_BACH"] == "1"
    out = bach_avoid_parallel_outer!(out) if bach_mode? || ENV.fetch("THEORY_PARALLELS", "1") != "0"
    out = annotate_theory!(out)
    out
  rescue StandardError => e
    warn "theory_runtime: #{e.message}" if ENV["DILLA_DEBUG"]
    chords
  end

  # Keep shared pitch classes between adjacent chords (Dilla/neo-soul glue).
  def dilla_common_tone_lock!(chords)
    (1...chords.length).each do |i|
      prev = Array(chords[i - 1][:hz]).map { |hz| hz_to_pc(hz) }
      curr_hz = Array(chords[i][:hz]).map(&:to_f).sort
      next if curr_hz.length < 2 || prev.empty?

      shared = prev & curr_hz.map { |hz| hz_to_pc(hz) }
      next if shared.empty?

      # Nudge nearest voice toward a common tone (same pitch class, closest octave).
      target_pc = shared.first
      best_j = nil
      best_cost = 1e9
      curr_hz.each_with_index do |hz, j|
        pc = hz_to_pc(hz)
        cost = [(pc - target_pc).abs, 12 - (pc - target_pc).abs].min
        if cost < best_cost
          best_cost = cost
          best_j = j
        end
      end
      next unless best_j && best_cost.positive? && best_cost <= 3

      midi = hz_to_midi(curr_hz[best_j])
      want = midi - ((midi.round - target_pc) % 12)
      # Snap to nearest pitch-class match within ±7 semitones.
      delta = ((target_pc - (midi.round % 12) + 6) % 12) - 6
      curr_hz[best_j] = midi_to_hz(midi + delta) if delta.abs <= 7
      chords[i] = chords[i].merge(hz: curr_hz.sort)
    end
    chords
  end

  # Prefer keeping lowest voice as pedal/slash color when progression is static-ish.
  def dilla_slash_pedal_bias!(chords, cfg)
    return chords if chords.length < 3

    pedal = Array(chords.first[:hz]).map(&:to_f).min
    return chords unless pedal&.positive?

    # Only apply light pedal on curated soul tracks / when THEORY_PEDAL=1.
    track = (cfg[:track] || ENV["TRACK"]).to_s
    allow = ENV["THEORY_PEDAL"] == "1" || track.match?(/neo_soul|dilla|untitled|slash|get_dis|donut|erykah/i)
    return chords unless allow

    (1...chords.length).each do |i|
      hz = Array(chords[i][:hz]).map(&:to_f).sort
      next if hz.length < 3

      # Replace lowest with pedal octave near original bass.
      bass = hz.first
      target = pedal
      target *= 2 while target * 2 < bass * 0.85
      target /= 2 while target > bass * 1.25 && target > 40
      hz[0] = target
      chords[i] = chords[i].merge(hz: hz.sort, bass_hz: target)
    end
    chords
  end

  # Smooth upper-voice motion (Bach-ish): minimize total stepwise distance.
  def bach_voice_lead!(chords)
    (1...chords.length).each do |i|
      prev = Array(chords[i - 1][:hz]).map(&:to_f).sort
      curr = Array(chords[i][:hz]).map(&:to_f).sort
      next if prev.empty? || curr.empty?

      n = [prev.length, curr.length].min
      led = Array.new(n)
      used = {}
      # Greedy: assign each previous voice to nearest unused current pitch-class tone.
      prev.first(n).each_with_index do |phz, vi|
        best = nil
        best_d = 1e9
        curr.each_with_index do |chz, ci|
          next if used[ci]
          d = (hz_to_midi(chz) - hz_to_midi(phz)).abs
          if d < best_d
            best_d = d
            best = ci
          end
        end
        if best
          used[best] = true
          # Octave-fold toward previous voice.
          pm = hz_to_midi(phz)
          cm = hz_to_midi(curr[best])
          while cm - pm > 6
            cm -= 12
          end
          while pm - cm > 6
            cm += 12
          end
          led[vi] = midi_to_hz(cm.clamp(DillaHarmony::PAD_MIDI_MIN, DillaHarmony::PAD_MIDI_MAX))
        end
      end
      led.compact!
      next if led.length < 2

      # Keep any unused upper extensions.
      extras = curr.reject.with_index { |_, ci| used[ci] }
      chords[i] = chords[i].merge(hz: (led + extras).sort.last([led.length + extras.length, 5].min))
    end
    chords
  end

  # Soften parallel 5ths/8ves between bass and soprano by nudging soprano.
  def bach_avoid_parallel_outer!(chords)
    (1...chords.length).each do |i|
      a = Array(chords[i - 1][:hz]).map(&:to_f).sort
      b = Array(chords[i][:hz]).map(&:to_f).sort
      next if a.length < 2 || b.length < 2

      ab, as_ = a.first, a.last
      bb, bs = b.first, b.last
      int_a = (hz_to_midi(as_) - hz_to_midi(ab)).round % 12
      int_b = (hz_to_midi(bs) - hz_to_midi(bb)).round % 12
      next unless [0, 7].include?(int_a) && int_a == int_b

      # Parallel perfect — drop soprano a whole step if possible.
      bs_m = hz_to_midi(bs) - 2
      b[-1] = midi_to_hz(bs_m.clamp(DillaHarmony::PAD_MIDI_MIN, DillaHarmony::PAD_MIDI_MAX))
      chords[i] = chords[i].merge(hz: b.sort)
    end
    chords
  end

  def annotate_theory!(chords)
    symbols = chords.map { |c| c[:name].to_s }
    insight = nil
    if defined?(DillaMusicGems) && DillaMusicGems.respond_to?(:progression_analysis)
      insight = DillaMusicGems.progression_analysis(symbols)
    end
    chords.each_with_index do |c, i|
      c[:theory] = {
        pc: Array(c[:hz]).map { |hz| hz_to_pc(hz) },
        insight: i.zero? ? insight : nil,
      }
    end
    chords
  end

  # Delegates to DillaHarmony's canonical conversions (harmony_engine.rb,
  # required before this file) so the two engines can't drift -- they used
  # to be reimplemented here with a different midi_to_hz rounding than
  # DillaHarmony's, so a chord tone processed by each carried different
  # precision and could fail exact-hz comparisons downstream.
  def hz_to_midi(hz)
    return 60.0 if hz.to_f <= 0
    DillaHarmony.hz_to_midi(hz.to_f)
  end

  def midi_to_hz(midi)
    DillaHarmony.midi_to_hz(midi.to_f)
  end

  def hz_to_pc(hz)
    hz_to_midi(hz).round % 12
  end
end
