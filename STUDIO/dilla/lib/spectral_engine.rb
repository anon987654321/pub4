# frozen_string_literal: true

# Spectral chop, arpeggiator, octave/partial stacks.
#
# Removed here: darkness_filter_chain, darkness_iterations, ir_transient_boost,
# phase_stretch_filter and spectral_reorder_paths, none of which had a caller
# anywhere in the engine. INDUSTRIAL_DARK, DARKNESS_ITERS, IR_TRANSIENT,
# PHASE_STRETCH and SPECTRAL_CHOP were read only by those five, so the
# --industrial-dark flag set an environment variable that nothing downstream
# ever looked at. The acrusher/afftfilt chain it described is in git history if
# it should be wired into render_industrial rather than dropped.
module DillaSpectral
  module_function

  def enabled?
    ENV["SPECTRAL_ENGINE"] != "0"
  end

  def chop_hz(chord, t = 0.0)
    hz = DillaHarmony.chop_tones(chord)[:hz]
    return hz if hz.empty?
    return spectral_arpeggiate(hz, t) if ENV["SPECTRAL_ARP"] == "1"
    return stack_hz(hz.min, t) if ENV["HARMONIC_STACK"] == "1"
    hz
  end

  def spectral_arpeggiate(hz, t)
    sorted = hz.sort
    band = ((t * 8).to_i) % sorted.length
    [sorted[band]]
  end

  # What HARMONIC_STACK has always produced, and NOT a harmonic series despite
  # the flag's name: successive OCTAVES of the fundamental. At 130.81 Hz that
  # is 130.8 / 261.6 / 523.2 / 1046.5 / 2093.0 / 4185.9 Hz -- five octaves of
  # reach, which is where the stack gets its top end. Keeping the name it has
  # been called by, with the behaviour stated.
  def octave_stack_hz(fundamental, _t = 0.0, count: 6)
    base_midi = DillaHarmony.hz_to_midi(fundamental)
    (1..count).map { |h| DillaHarmony.midi_to_hz(base_midi + (h - 1) * 12) }
  end

  # Fletcher stiff-string partials: f_n = n * f0 * sqrt(1 + B*n^2), from the
  # wave equation for a string with bending stiffness (Fletcher, Blackham &
  # Stratton 1962). Higher partials are progressively sharp, which is the
  # physical origin of the Railsback stretch in piano tuning. Measured B runs
  # ~1e-5..5e-5 on piano treble, ~1e-4..1e-3 on wound bass strings; 2.5e-4 puts
  # the sixth partial 7.8 cents sharp -- present, not a detune effect.
  #
  # This is a different series from octave_stack_hz, not a coloured version of
  # it: six partials of 130.81 Hz top out at 788 Hz where six octaves reach
  # 4186 Hz. Swapping it in as the default would take 2.4 octaves off the top
  # of every HARMONIC_STACK render, and RENDER_MODE=warp sets that flag, so it
  # is opt-in under INHARMONIC=1 like every other flag here.
  #
  # No drift term on B. A slow +-0.15% wobble on B moves the sixth partial by
  # 0.023 cents against a discrimination limit around 5 cents, so it would be
  # arithmetic nobody can hear; the f0 drift is what carries the movement, and
  # at +-0.08% it is worth 2.8 cents peak to peak.
  INHARMONIC_B = 0.00025
  INHARMONIC_DRIFT = 0.0008

  def inharmonic_stack_hz(fundamental, t = 0.0, count: 6, b: nil)
    f0 = fundamental.to_f
    return [] unless f0.positive?

    b = (b || ENV.fetch("INHARMONIC_B", INHARMONIC_B)).to_f.clamp(0.0, 0.01)
    f0 *= 1.0 + (INHARMONIC_DRIFT * Math.sin((t * 0.37) + (f0 * 0.0011))) if ENV["INHARMONIC_DRIFT"] != "0"
    (1..count).map { |n| (n * f0 * Math.sqrt(1.0 + (b * n * n))).round(4) }
  end

  def stack_hz(fundamental, t = 0.0, count: 6)
    return inharmonic_stack_hz(fundamental, t, count:) if ENV["INHARMONIC"] == "1"

    octave_stack_hz(fundamental, t, count:)
  end

  def breath_perc_hz
    [180.0, 220.0, 280.0, 340.0]
  end

  def breath_mode?
    ENV["BREATH_PERC"] == "1"
  end
end
