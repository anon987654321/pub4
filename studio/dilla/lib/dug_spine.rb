# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require_relative "crate_dig"
require_relative "dug_montage"

# The montage as the track's spine, with the engine's beat underneath.
#
# The obvious route was SAMPLE_LOOP, and it is wrong: that hook takes a loop of
# a few bars and colours a whole track with it, and cross_sample_process builds
# a filter graph proportional to the source. Handed a 260-second montage it
# produced 790kb of filtergraph -- too large for a command line, passed to
# ffmpeg through a script file -- and the stream spent six minutes on one track
# without reaching audio. Worse than slow, it was wrong musically: 35 sources
# averaged into a single colour rather than a track that moves through them.
#
# So the montage stays a montage. It is graded through the engine's own analog
# chain, the beat is rendered separately and tiled to length, and the two are
# mixed with the beat ducking under the spine. The sides stay distinct and in
# sequence, which is what "all of them in one track" has to mean.
module DugSpine
  RENDERS = File.join(CrateDig::ROOT, "renders")
  OUT = File.join(RENDERS, "dug_spine.wav")
  SPINE_GRADE = "vinyl_lab"

  module_function

  def duration(path)
    `ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 #{path.inspect} 2>/dev/null`.to_f
  end

  def sh!(*argv)
    system(*argv, out: File::NULL, err: File::NULL) or raise "failed: #{argv.first}"
  end

  # The engine renders a fixed number of bars; the spine is however long the
  # crate made it. Tiling the beat to the spine keeps the arrangement honest --
  # padding with silence would leave the last sides bare, and stretching the
  # beat would detune the drums.
  def tile_to(beat, seconds, dest)
    sh!("ffmpeg", "-v", "error", "-y", "-stream_loop", "-1", "-i", beat,
        "-t", format("%.3f", seconds), "-ar", "44100", "-ac", "2",
        "-c:a", "pcm_s16le", dest)
    dest
  end

  # Beat under spine, not beside it. sidechaincompress keyed off the spine means
  # the drums breathe around the record rather than fighting it for the same
  # 200-2500Hz band the 78s occupy -- which is where all their musical content
  # is, and where a kick and a bass also live.
  def mix!(spine, beat, dest, spine_gain: 1.0, beat_gain: 0.72)
    graph = [
      "[0:a]volume=#{spine_gain},asplit=2[sp][key]",
      "[1:a]volume=#{beat_gain}[bt]",
      "[bt][key]sidechaincompress=threshold=0.05:ratio=4:attack=8:release=220[btduck]",
      "[sp][btduck]amix=inputs=2:duration=first:dropout_transition=0,"     \
      "alimiter=limit=0.95:level_out=0.94,loudnorm=I=-14:TP=-1.0:LRA=11[out]",
    ].join(";")
    sh!("ffmpeg", "-v", "error", "-y", "-i", spine, "-i", beat,
        "-filter_complex", graph, "-map", "[out]",
        "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", dest)
    dest
  end

  # The engine's own grade, not a hand-rolled chain. vinyl_lab is
  # spectral_warmth → tape_saturation → harmonic_bloom → platter_wow →
  # vinyl_crackle → stylus_mistrack → needle_drop_fade → analog_noise: eight
  # stages, and the right eight for material that is already a 78 transfer.
  #
  # Run as a subprocess rather than by calling grade() directly, so this module
  # stays loadable on its own and the chain stays the one dilla.rb defines
  # instead of a copy of it that can drift.
  def grade!(input, output, preset)
    ruby = File.join(CrateDig::ROOT, "dilla.rb")
    sh!(RbConfig.ruby, ruby, "grade", input, output, preset)
    output
  end

  # beat_path is rendered by the caller — dilla.rb owns the engine and this
  # module only assembles. That split means the spine can be remixed against a
  # different beat, or at a different balance, without re-rendering anything.
  def build!(beat_path, out: OUT, montage: DugMontage::OUT, grade_preset: SPINE_GRADE)
    raise "no montage — run the montage build first" unless File.file?(montage)
    raise "no beat at #{beat_path}" unless File.file?(beat_path)

    FileUtils.mkdir_p(RENDERS)
    seconds = duration(montage)
    tmp = File.join(CrateDig::DUG, ".spine")
    FileUtils.mkdir_p(tmp)
    graded = File.join(tmp, "spine_graded.wav")
    tiled = File.join(tmp, "beat_tiled.wav")

    puts "  grading spine through #{grade_preset} (#{seconds.round(1)}s)..."
    grade!(montage, graded, grade_preset)
    puts "  tiling beat to #{seconds.round(1)}s..."
    tile_to(beat_path, seconds, tiled)
    puts "  mixing (beat ducked under spine)..."
    mix!(graded, tiled, out)

    FileUtils.rm_rf(tmp)
    puts "spine: #{duration(out).round(1)}s → #{out.sub("#{CrateDig::ROOT}/", '')}"
    out
  end
end
