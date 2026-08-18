# frozen_string_literal: true
#
# Synthesised samples: shakers, cowbells, Karplus-Strong plucks, layered kicks.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def load_mono_sample(path)
  floats = DillaMusicGems.read_mono_wav(path) if defined?(DillaMusicGems)
  return floats if floats&.any?
  pipe_floats(path, "aformat=channel_layouts=mono:sample_fmts=flt")
end

# Abstract-kit kicks are never one thin
# sample — they stack a pitch-dropping sub body for weight, a short
# broadband click for attack/definition, and mild saturation for character.
# Layers on top of the existing sample rather than replacing it.
# Synthesized since no shaker/cowbell samples exist in the kit — filtered
# noise burst for the shaker (broadband "shhh" with a fast-then-slow
# double-envelope, real shaker physics: an initial hit then beads settling)
def synth_shaker_sample(seed: 11)
  len = (0.09 * SAMPLE_RATE).round
  rng = Random.new(seed)
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 24.0) + 0.3 * Math.exp(-t * 60.0)
    out[i] = 0.5 * env * (rng.rand * 2.0 - 1.0)
  end
  peak = out.map(&:abs).max || 1.0
  out.map { |s| s / [peak, 0.01].max * 0.8 }
end

# Classic two-oscillator 808/909 cowbell: two square-ish tones (540Hz and
# 800Hz, the real ratio used in analog cowbell circuits) with a fast decay.
def synth_cowbell_sample
  len = (0.18 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 14.0)
    tone1 = Math.sin(2 * Math::PI * 540.0 * t) > 0 ? 1.0 : -1.0
    tone2 = Math.sin(2 * Math::PI * 800.0 * t) > 0 ? 1.0 : -1.0
    out[i] = 0.42 * env * (0.6 * tone1 + 0.4 * tone2)
  end
  out
end

# Karplus-Strong plucked-string synthesis (Stanford/CCRMA algorithm,
# exact) — a genuinely new instrument timbre, not another oscillator/
# soundfont voice. Fill a ring buffer of noise, then average adjacent
# samples with a stretch factor for decay/damping control.
def karplus_strong_pluck(freq, duration_sec, seed: nil, stretch: 0.996, damping: 0.5)
  n = (SAMPLE_RATE / freq).round.clamp(2, SAMPLE_RATE)
  rng = seed ? Random.new(seed) : Random.new
  buf = Array.new(n) { rng.rand * 2.0 - 1.0 }
  total = (duration_sec * SAMPLE_RATE).round
  out = Array.new(total, 0.0)
  total.times do |i|
    idx = i % n
    if i < n
      out[i] = buf[idx]
    else
      prev = out[i - n]
      prev2 = out[i - n - 1] || prev
      averaged = damping * prev + (1.0 - damping) * prev2
      out[i] = stretch * averaged
    end
  end
  out
end

def raw_kick_samples?
  return true if ENV["RAW_KICK"] == "1" || ENV["DRUM_SAMPLE_RAW"] == "1"
  return true if comfort_mode?
  return true if ENV["EXTERNAL_KIT"] && !ENV["EXTERNAL_KIT"].empty?

  path = drum_sample_path("kick.wav")
  path&.start_with?(CUSTOM_DRUM_DIR)
end

def normalize_drum_sample(samples, peak: 0.7)
  return samples if samples.nil? || samples.empty?

  max = samples.map(&:abs).max || 1.0
  return samples if max < 1.0e-6

  mul = peak / max
  samples.map { |s| s * mul }
end

# Install EXTERNAL_KIT oneshots into samples/drums/custom/ once so
# drum_sample_path prefers them over synthesized DRUM_DIR files.
def ensure_external_kit_installed!
  kit = ENV["EXTERNAL_KIT"].to_s
  return if kit.empty?

  marker = File.join(CUSTOM_DRUM_DIR, ".external_kit")
  if File.file?(marker) && File.read(marker).strip == kit && File.file?(File.join(CUSTOM_DRUM_DIR, "kick.wav"))
    return
  end

  FileUtils.mkdir_p(CUSTOM_DRUM_DIR)

  if kit == "industrial" || kit == "industrial_techno"
    # Built-in industrial one-shots under samples/drums/ind_*.
    mapping = {
      "kick.wav" => "ind_kick.wav",
      "snare.wav" => "ind_clap.wav",
      "ghost.wav" => "ind_clap.wav",
      "hat.wav" => "ind_hat.wav",
      "open_hat.wav" => "ind_hat.wav",
      "bass_43.wav" => "ind_bass_e.wav",
    }
    mapping.each do |dest_name, src_name|
      src = File.join(DRUM_DIR, src_name)
      next unless File.file?(src)

      FileUtils.cp(src, File.join(CUSTOM_DRUM_DIR, dest_name))
    end
    File.write(marker, kit)
    dmesg("industrial kit → custom/", unit: "drums0", parent: "dilla0") if respond_to?(:dmesg)
    return
  end

  src_dir = File.join(EXTERNAL_DRUM_KIT_CACHE, "drum-samples", kit)
  return unless Dir.exist?(src_dir)

  {
    "kick.wav" => "kicks", "snare.wav" => "snares", "hat.wav" => "hi-hats",
    "open_hat.wav" => "open-hats", "ghost.wav" => "claps", "bass_43.wav" => "808s"
  }.each do |dest_name, subdir|
    candidates = Dir.glob(File.join(src_dir, subdir, "*.wav")).sort_by { |f| File.size(f) }
    src = candidates[candidates.length / 2] || candidates.first
    next unless src

    FileUtils.cp(src, File.join(CUSTOM_DRUM_DIR, dest_name))
  end
  File.write(marker, kit)
  dmesg("external kit #{kit} → custom/", unit: "drums0", parent: "dilla0") if respond_to?(:dmesg)
rescue StandardError => e
  warn "ensure_external_kit_installed!: #{e.message}"
end

def layered_kick_sample(base_sample, seed: 7)
  # True 808-style envelope, not a short punch: a fast pitch drop (150Hz ->
  # 42Hz over ~55ms, the "pluck") into a genuinely sustained low tone
  # (~350ms total, slow decay) — the long boom is the whole point of an
  # 808, not an incidental side effect of layering.
  sub_len = (0.35 * SAMPLE_RATE).round
  click_len = (0.009 * SAMPLE_RATE).round
  out = base_sample.dup
  out.concat(Array.new(sub_len - out.length, 0.0)) if out.length < sub_len
  sub_len.times do |i|
    t = i.to_f / SAMPLE_RATE
    pitch = 42.0 + 108.0 * Math.exp(-t * 55.0)
    env = Math.exp(-t * 9.0)
    out[i] += 0.34 * env * Math.sin(2 * Math::PI * pitch * t)
  end
  rng = Random.new(seed)
  click_len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 380.0)
    out[i] += 0.14 * env * (rng.rand * 2.0 - 1.0)
  end
  # Body layer: a short mid-punch (~150Hz) between the sub and the click —
  # definition that survives on small speakers where the 42Hz fundamental
  # barely reproduces at all.
  body_len = (0.05 * SAMPLE_RATE).round
  body_len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 55.0)
    out[i] += 0.18 * env * Math.sin(2 * Math::PI * 150.0 * t)
  end
  peak = out.map(&:abs).max || 1.0
  gain = peak > 0.95 ? 0.95 / peak : 1.0
  # A single gentle saturation pass, not stacked with anything downstream —
  # double saturation (this plus a second stage on the whole drum bus) is
  # what made it sound bad, not the layering itself.
  drive = 1.1
  ceiling = Math.tanh(drive)
  # Old formula (0.16*KICK_GAIN+0.06) crushed kicks to ~0.2 peak before the bus —
  # inaudible under pads. Camel/FlyLo needs near-unity sample level.
  sample_mul = if flylo_primary_drums?
                 ENV.fetch("KICK_SAMPLE_GAIN", "0.95").to_f.clamp(0.4, 1.2)
               else
                 (0.16 * kick_velocity_scale + 0.06).clamp(0.08, 0.55)
               end
  out.map { |s| (Math.tanh(s * gain * drive) / ceiling) * sample_mul }
end

def mix_sine!(left, right, frame, frames_n, hz, amp, decay: 2.6, mod_hz: 0.23, chorus: false,
              source_offset: 0)
  voices = if chorus
             [{ cents: 0.0, pan: 0.0, gain: 0.55 }, { cents: 5.5, pan: -0.42, gain: 0.28 },
              { cents: -5.5, pan: 0.42, gain: 0.28 }, { cents: 11.0, pan: -0.18, gain: 0.12 }]
           else
             [{ cents: 0.0, pan: 0.0, gain: 1.0 }]
           end
  frames_n.times do |i|
    idx = frame + i
    break if idx >= left.length
    t = (source_offset + i).to_f / SAMPLE_RATE
    env = Math.exp(-t * decay) * (0.78 + 0.22 * Math.sin(2 * Math::PI * mod_hz * t))
    voices.each do |voice|
      fh = hz * (2 ** (voice[:cents] / 1200.0))
      s = amp * voice[:gain] * env * Math.sin(2 * Math::PI * fh * t)
      pan = voice[:pan]
      left[idx]  += s * (0.5 - pan * 0.5)
      right[idx] += s * (0.5 + pan * 0.5)
    end
  end
end
