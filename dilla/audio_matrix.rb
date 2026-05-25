# frozen_string_literal: true

require "shellwords"

class AudioMatrix
  def initialize(bpm: 92, swing: 0.05)
    @bpm = bpm
    @swing = swing
    @events = []
  end

  def add_sample(step:, file_path:, velocity: 1.0)
    step_duration = 60.0 / @bpm / 4.0
    swing_offset = (step % 2 != 0) ? @swing * step_duration : 0.0
    timestamp = (step * step_duration) + swing_offset
    @events << { time: timestamp.round(4), path: file_path, vol: velocity }
  end

  def compile(output_file = "output.wav")
    parts = @events.flat_map.with_index { |ev, idx|
      [Shellwords.shellescape(ev[:path]), "_tmp_#{idx}.wav", "pad", ev[:time].to_s, "0", "vol", ev[:vol].to_s]
    }
    system("sox", "-m", *parts, output_file)
  ensure
    clean_temporary_stems
  end

  def clean_temporary_stems
    Dir.glob("_tmp_*.wav").each { |f| File.delete(f) }
  end

  def detect_transients(pcm_file)
    io = File.open(pcm_file, "rb")
    peaks = []
    idx = 0
    while (chunk = io.read(1024))
      samples = chunk.unpack("s*")
      energy = samples.map(&:abs).sum / samples.size.to_f
      peaks << idx if energy > 15000
      idx += 1
    end
    peaks
  end

  def inject_vinyl_crackle(track_file, intensity = 0.1)
    duration = IO.popen(["soxi", "-D", track_file], err: File::NULL) { |io| io.read }.strip
    system("sox", "-n", "-r", "44100", "-b", "16", "_crackle.wav",
           "synth", duration, "whitenoise", "vol", intensity.to_s)
    system("sox", "-m", track_file, "_crackle.wav", "_final_mix.wav")
    File.rename("_final_mix.wav", track_file)
  ensure
    File.delete("_crackle.wav") if File.exist?("_crackle.wav")
  end

  def export_stems(target_directory)
    Dir.mkdir(target_directory) unless Dir.exist?(target_directory)
    @events.group_by { |e| e[:path] }.each do |path, evs|
      stem_name = File.basename(path, ".*")
      parts = evs.flat_map.with_index { |ev, idx|
        [Shellwords.shellescape(ev[:path]), "_stem_tmp_#{idx}.wav", "pad", ev[:time].to_s, "0", "vol", ev[:vol].to_s]
      }
      system("sox", "-m", *parts, File.join(target_directory, "#{stem_name}_stem.wav"))
      Dir.glob("_stem_tmp_*.wav").each { |f| File.delete(f) }
    end
  end

  def apply_lofi_filter!(track_file)
    system("sox", track_file, "_filtered.wav", "lowpass", "1200", "vol", "0.95")
    File.rename("_filtered.wav", track_file)
  end
end
