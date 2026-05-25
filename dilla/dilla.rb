# frozen_string_literal: true

require "shellwords"

class Dilla
  def initialize(bpm: 92, swing: 0.05)
    @bpm = bpm
    @swing = swing
    @tracks = []
  end

  def add_track(step, file, vol = 1.0)
    step_dur = 60.0 / @bpm / 4.0
    offset = (step % 2 != 0) ? @swing * step_dur : 0.0
    @tracks << { time: (step * step_dur) + offset, path: file, vol: vol }
  end

  def compile(out = "dilla_mix.wav")
    parts = @tracks.flat_map.with_index { |t, i|
      [Shellwords.shellescape(t[:path]), "_tmp_#{i}.wav", "pad", t[:time].round(4).to_s, "0", "vol", t[:vol].to_s]
    }
    system("sox", "-m", *parts, out)
    system("sox", out, "filtered_#{out}", "lowpass", "1200", "vol", "0.95")
    File.rename("filtered_#{out}", out)
  ensure
    Dir.glob("_tmp_*.wav").each { |f| File.delete(f) }
  end
end

if __FILE__ == $PROGRAM_NAME
  d = Dilla.new
  d.compile
end
