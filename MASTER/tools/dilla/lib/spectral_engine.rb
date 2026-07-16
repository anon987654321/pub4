# frozen_string_literal: true

# Spectral chop, arpeggiator, harmonic stack, industrial darkness.
module DillaSpectral
  module_function

  def enabled?
    ENV["SPECTRAL_ENGINE"] != "0"
  end

  def chop_hz(chord, t = 0.0)
    hz = DillaHarmony.chop_tones(chord)[:hz]
    return hz if hz.empty?
    return spectral_arpeggiate(hz, t) if ENV["SPECTRAL_ARP"] == "1"
    return harmonic_stack_hz(hz.min, t) if ENV["HARMONIC_STACK"] == "1"
    hz
  end

  def spectral_arpeggiate(hz, t)
    sorted = hz.sort
    band = ((t * 8).to_i) % sorted.length
    [sorted[band]]
  end

  def harmonic_stack_hz(fundamental, t, count: 6)
    base_midi = DillaHarmony.hz_to_midi(fundamental)
    (1..count).map { |h| DillaHarmony.midi_to_hz(base_midi + (h - 1) * 12) }
  end

  def darkness_iterations
    enabled? && ENV["INDUSTRIAL_DARK"] == "1" ? (ENV["DARKNESS_ITERS"] || 3).to_i : 0
  end

  def darkness_filter_chain
    iters = darkness_iterations
    return "" if iters.zero?
    parts = []
    iters.times { parts << "acrusher=bits=10:samples=1.2:mix=0.22,afftfilt=real='re*1.1':imag='im*1.1'" }
    parts.join(",")
  end

  def ir_transient_boost
    ENV["IR_TRANSIENT"] == "1"
  end

  def phase_stretch_filter
    ENV["PHASE_STRETCH"] == "1" ? "rubberband=tempo=0.5" : nil
  end

  def spectral_reorder_paths(sample_dir, count: 8)
    return [] unless enabled? && ENV["SPECTRAL_CHOP"] == "1"
    files = Dir.glob(File.join(sample_dir, "**", "*.{wav,mp3}")).first(count * 2)
    files.sort_by { |f| File.basename(f).hash.abs }.first(count)
  end

  def breath_perc_hz
    [180.0, 220.0, 280.0, 340.0]
  end

  def breath_mode?
    ENV["BREATH_PERC"] == "1"
  end
end