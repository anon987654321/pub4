# frozen_string_literal: true

# Slice one-shot kicks/snares/hats from Flying Lotus — Camel demucs drums for FlyLo mode.
# Forum/Reddit consensus: FlyLo kits are layered, crunchy, not generic GM samples.
module DillaCamelChops
  module_function

  SOURCE_REL = "samples/demux/htdemucs_6s/flylo_camel_source/drums.wav"
  OUT_DIR_REL = "samples/drums/custom/camel_chops"
  BPM = 86.0

  def source_path(root)
    File.join(root, SOURCE_REL)
  end

  def out_dir(root)
    File.join(root, OUT_DIR_REL)
  end

  def ready?(root)
    d = out_dir(root)
    %w[kick.wav snare.wav hat.wav].all? { |n| File.file?(File.join(d, n)) }
  end

  # Extract short one-shots at grid anchors (16th notes @ 86 BPM).
  def ensure!(root, ffmpeg: "ffmpeg")
    return out_dir(root) if ready?(root)
    src = source_path(root)
    return nil unless File.file?(src)

    dest = out_dir(root)
    FileUtils.mkdir_p(dest)
    step = 60.0 / BPM / 4.0
    # Anchor hits from FLYLO_CAMEL_DRUM_GRID research (kick 0, snare 4, hat 2).
    slices = {
      "kick.wav" => 0 * step + 0.5,   # start mid-track for denser hits
      "snare.wav" => 4 * step + 0.5,
      "hat.wav" => 2 * step + 0.5
    }
    # Prefer later bars where kit is denser (~ bar 8 = 8*4*step)
    bar8 = 8 * 4 * step
    slices.each do |name, offset|
      t0 = (bar8 + offset).round(3)
      dur = name.start_with?("kick") ? 0.28 : (name.start_with?("snare") ? 0.22 : 0.12)
      out = File.join(dest, name)
      system(ffmpeg, "-y", "-ss", t0.to_s, "-t", dur.to_s, "-i", src,
             "-af", "aformat=sample_rates=44100:channel_layouts=mono,highpass=f=30,alimiter=limit=0.95",
             "-c:a", "pcm_s16le", out, out: File::NULL, err: File::NULL)
    end
    ready?(root) ? dest : nil
  end

  def apply_to_kit!(kit, root)
    d = ensure!(root)
    return kit unless d
    { kick: "kick.wav", snare: "snare.wav", hat: "hat.wav" }.each do |role, file|
      path = File.join(d, file)
      next unless File.file?(path)
      samples = DillaMusicGems.read_mono_wav(path) if defined?(DillaMusicGems)
      if samples.nil? || samples.empty?
        # ffmpeg-load via engine helper if present
        samples = load_wav_mono_simple(path)
      end
      kit[role] = samples if samples && !samples.empty?
    end
    kit
  end

  def load_wav_mono_simple(path)
    return nil unless File.file?(path)
    # Prefer wavefile via gems; fallback nil (kit keeps default sample).
    return nil unless defined?(DillaMusicGems) && DillaMusicGems.wavefile?
    DillaMusicGems.read_mono_wav(path)
  rescue StandardError
    nil
  end
end
