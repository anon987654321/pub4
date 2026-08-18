# frozen_string_literal: true
#
# The punk guitar layer.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def punk_guitar_enabled?
  ENV["PUNK_GUITAR"] == "1"
end

# Straight (unswung) sixteenth-note downstroke chug -- root+5th only, no
# third -- through the existing dist_guitar GM patch, dropped an octave so
# it sits below the Rhodes/pad register instead of fighting it. Deliberately
# ignores the swung Dilla drum grid: the contrast between machine-straight
# punk strumming and the humanized kit is the point. Accented on-beat hits
# vs. quieter/shorter off-beat palm-mutes (classic downstroke gallop), with
# occasional syncopated rests so it doesn't read as a machine-gun wall.
# Follows the same chord roots as the main progression, cycled per bar.
def render_punk_guitar_layer!(beat_bpm, n_bars, cfg)
  return nil unless fluidsynth_pad_available?
  names = CHORD_PROGRESSIONS[cfg[:progression]] || CHORD_PROGRESSIONS.fetch(:soul)
  return nil if names.empty?
  beat_p = 60.0 / beat_bpm.to_f
  step = beat_p / 4.0
  bar_len = beat_p * 4.0
  duration = bar_len * n_bars
  rng = Random.new(42)
  events = []
  (duration / step).floor.times do |i|
    on_beat = (i % 4).zero?
    next if !on_beat && rng.rand < 0.15
    t = i * step
    chord = PAD_CHORD_LOOKUP[names[(t / bar_len).floor % names.length]]
    next unless chord && chord[:hz]&.any?
    root = chord[:hz].min / 2.0
    fifth = root * (2**(7.0 / 12.0))
    vel = on_beat ? 0.95 : 0.5
    sustain = on_beat ? step * 0.7 : step * 0.3
    events << [t, vel, { hz: [root, fifth] }, sustain]
  end
  return nil if events.empty?
  voice = patch_voice_for(synth_patch_by_id(:dist_guitar))
  return nil unless voice
  dir = Dir.mktmpdir("punk_guitar")
  path = File.join(dir, "guitar.wav")
  midi_path = "#{path}.mid"
  write_smf(midi_path, events, program: voice[:program], bank: voice[:bank] || 0, duration:, lead_mode: true)
  fluidsynth_render!(path, voice[:sf2], midi_path, gain: 1.2)
  FileUtils.rm_f(midi_path)
  path
end

# Amp crunch, dialed back: highpass off the low end (kick/bass own that
# range), a mid scoop around 700Hz to carve space from the Rhodes/pad
# instead of competing with it, gentler compression, and a light bit-crush
# for grit rather than heavy distortion. Sits under the beat by weight --
# same amix-not-sidechain discipline as the vocal layer.
def mix_punk_guitar_layer!(beat_path, guitar_path, dest)
  gtr_vol = ENV.fetch("PUNK_GUITAR_MIX", "0.85").to_f
  bed_w = ENV.fetch("PUNK_GUITAR_BED_WEIGHT", "1.0").to_f
  gtr_w = ENV.fetch("PUNK_GUITAR_WEIGHT", "0.5").to_f
  lowpass_hz = ENV.fetch("PUNK_GUITAR_LOWPASS", "5200").to_f
  filter = [
    "[1:a]aformat=channel_layouts=stereo,highpass=f=110,lowpass=f=#{lowpass_hz}," \
    "equalizer=f=700:t=o:w=1.5:g=-4," \
    "acompressor=threshold=-14dB:ratio=4:attack=5:release=80," \
    "acrusher=bits=12:samples=2:mix=0.08,volume=#{gtr_vol}[g0]",
    "[0:a][g0]amix=inputs=2:weights=#{bed_w} #{gtr_w}:duration=first:dropout_transition=0:normalize=0," \
    "alimiter=limit=0.96:level_out=0.97[out]",
  ].join(";")
  sh! "ffmpeg", "-y", "-i", beat_path, "-i", guitar_path,
      "-filter_complex", filter,
      "-map", "[out]", *codec_for(dest), dest
end
