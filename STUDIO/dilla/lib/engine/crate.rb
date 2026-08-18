# frozen_string_literal: true
#
# Building the crate, and importing/exporting drum MIDI.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- the crate ----------------------------------------------------------------
#
# One-shots and sustains to chop, synthesised rather than dug for. Every voice
# here is built from oscillators and filtered noise, so the crate carries no
# provenance question and can be regenerated on any machine from this file
# alone -- which is also why it is a command and not a folder of wav files
# committed once and never reproducible.
#
# The tonal voices are additive: a harmonic series with per-instrument weights
# and an envelope. That is not a sampled Rhodes and does not pretend to be one,
# but a Rhodes IS a struck tine with a bell-like odd-harmonic spectrum and a
# fast attack, and additive synthesis reproduces that description directly.
CRATE_DIR = File.join(SAMPLE_DIR, "crate").freeze

# [harmonic, amplitude] pairs. Rhodes leans odd (tine), vibes are nearly pure
# with a slow beat, the analog voices carry a full series shaped by the filter.
CRATE_VOICES = {
  rhodes:   { harmonics: [[1, 1.0], [2, 0.28], [3, 0.42], [5, 0.16], [7, 0.08]],
              attack: 0.004, decay: 2.8, lowpass: 3800, trem: 0.0 },
  vibes:    { harmonics: [[1, 1.0], [4, 0.18], [9, 0.06]],
              attack: 0.002, decay: 3.6, lowpass: 5200, trem: 5.5 },
  cs80:     { harmonics: [[1, 1.0], [2, 0.5], [3, 0.33], [4, 0.25], [5, 0.2], [6, 0.16]],
              attack: 0.35, decay: 4.0, lowpass: 2600, trem: 0.0 },
  prophet:  { harmonics: [[1, 1.0], [2, 0.45], [3, 0.3], [4, 0.2], [6, 0.12]],
              attack: 0.12, decay: 3.2, lowpass: 3200, trem: 0.0 },
  jupiter:  { harmonics: [[1, 1.0], [2, 0.55], [3, 0.4], [5, 0.22], [7, 0.14], [9, 0.09]],
              attack: 0.02, decay: 2.2, lowpass: 4400, trem: 0.0 },
}.freeze

# Chords worth having under the fingers, in the keys the sampled loops read as.
CRATE_CHORDS = { "Cm9" => [130.81, "m9"], "Fm9" => [174.61, "m9"],
                 "Ebmaj9" => [155.56, "maj9"], "Gm9" => [196.00, "m9"],
                 "Dmaj9" => [146.83, "maj9"], "Am7b5" => [220.00, "m7b5"] }.freeze

def crate_tonal_expr(freqs, voice)
  spec = CRATE_VOICES.fetch(voice)
  terms = freqs.flat_map do |f|
    spec[:harmonics].map do |mult, amp|
      hz = (f * mult).round(3)
      next nil if hz > 16_000

      "#{(amp / freqs.size / spec[:harmonics].size * 2.4).round(5)}*sin(2*PI*#{hz}*t)"
    end.compact
  end
  # Struck envelope: near-instant rise, exponential fall. `trem` adds the slow
  # amplitude beat a vibraphone's rotating discs produce.
  env = "(1-exp(-t/#{spec[:attack]}))*exp(-t/#{spec[:decay]})"
  env = "#{env}*(1+#{(0.22).round(3)}*sin(2*PI*#{spec[:trem]}*t))" if spec[:trem].positive?
  ["(#{terms.join('+')})*#{env}", spec[:lowpass]]
end

# Noise textures. Crackle is impulsive and sparse, hiss is steady and bright,
# rumble is slow and almost sub -- three different things that all get called
# "vinyl noise" and do not substitute for each other.
CRATE_TEXTURES = {
  vinyl_crackle: "anoisesrc=color=white:amplitude=0.5:seed=#{noise_seed(25)}," \
                 "highpass=f=1200,lowpass=f=9000," \
                 "acompressor=threshold=-46dB:ratio=20:attack=0.05:release=8," \
                 "volume=7dB",
  tape_hiss:     "anoisesrc=color=white:amplitude=0.06:seed=#{noise_seed(26)},highpass=f=2500,lowpass=f=13000",
  turntable_rumble: "anoisesrc=color=brown:amplitude=0.5:seed=#{noise_seed(27)},lowpass=f=90,volume=4dB",
  room_tone:     "anoisesrc=color=pink:amplitude=0.12:seed=#{noise_seed(28)},highpass=f=120,lowpass=f=2200,volume=-6dB",
}.freeze

# Percussion, synthesised the way the physical thing works: a brush is noise
# with a fast decay, a conga is a pitched body with a noise transient, a shaker
# is a burst of high noise and nothing else.
CRATE_PERCUSSION = {
  brush_hit:  "anoisesrc=color=white:amplitude=0.8:seed=#{noise_seed(29)},highpass=f=900,lowpass=f=7000," \
              "afade=t=out:st=0:d=0.28",
  shaker:     "anoisesrc=color=white:amplitude=0.7:seed=#{noise_seed(30)},highpass=f=5000," \
              "afade=t=out:st=0:d=0.09",
  conga:      "aevalsrc='0.8*sin(2*PI*196*t)*exp(-t/0.22)+0.3*sin(2*PI*300*t)*exp(-t/0.09)':d=1," \
              "lowpass=f=2600",
  rimshot:    "aevalsrc='0.7*sin(2*PI*420*t)*exp(-t/0.035)':d=0.4,highpass=f=250",
}.freeze

# The texture and percussion strings BEGIN with a generator (anoisesrc,
# aevalsrc), so they are the input graph, not a filter applied to one. Chaining
# them onto an anullsrc input fails: a source filter cannot take an input.
def crate_render_one!(dest, generator, duration, lowpass: nil)
  post = []
  post << "lowpass=f=#{lowpass}" if lowpass
  post << "afade=t=out:st=#{[(duration - 0.05), 0].max.round(3)}:d=0.05"
  sh! "ffmpeg", "-y", "-f", "lavfi", "-i", generator,
      "-af", post.join(","), "-t", duration.to_s,
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest
  dest
end

# Reads a folder of MIDI drum clips and reports them as 16-step grids.
#
# A third provenance category, kept distinct from the other two: these are
# neither transcriptions of records nor constructions of mine, but patterns
# supplied in a pack the operator licensed. Being able to say which of the three
# a grid is matters more than having more grids.
#
# Note density is deliberately split rather than flattened: a MIDI snare part
# usually has two or three structural hits and a tail of ghost notes, and
# folding them together produces a grid that reads as busy rather than as a
# backbeat with detail under it. The loudest velocities become the part, the
# rest become ghosts.
def midi_drum_grid(path, ghost_below: 0.72)
  require "midilib"
  seq = MIDI::Sequence.new
  File.open(path, "rb") { |io| seq.read(io) }
  hits = []
  seq.each do |track|
    track.each do |ev|
      next unless ev.is_a?(MIDI::NoteOn) && ev.velocity.positive?

      hits << [((ev.time_from_start.to_f / seq.ppqn) * 4).round % 16, ev.velocity]
    end
  end
  return { steps: [], ghosts: [] } if hits.empty?

  peak = hits.map(&:last).max.to_f
  loud = hits.select { |(_, v)| v >= peak * ghost_below }.map(&:first).uniq.sort
  soft = hits.reject { |(_, v)| v >= peak * ghost_below }.map(&:first).uniq.sort - loud
  { steps: loud, ghosts: soft }
rescue StandardError => e
  warn "midi #{File.basename(path)}: #{e.message}"
  { steps: [], ghosts: [] }
end

def import_midi_drums!(dir)
  unless File.directory?(dir)
    warn "import-midi: no such directory #{dir}"
    return
  end

  groups = Hash.new { |h, k| h[k] = [] }
  Dir[File.join(dir, "**", "*.mid")].sort.each do |f|
    name = File.basename(f, ".mid").downcase
    role = case name
           when /open\s*hat|open_hat/ then :open
           when /hi\s*hat|hihat|hat/ then :hats
           when /kick|bd/ then :kicks
           when /snare|sd|clap/ then :snares
           when /perc|rim|tom|conga|shaker/ then :perc
           else next
           end
    groups[role] << [f, midi_drum_grid(f)]
  end

  if groups.empty?
    warn "import-midi: no kick/snare/hat clips found in #{dir}"
    return
  end

  slug = File.basename(dir).to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
  slug = "pack" if slug.empty?
  count = [groups[:kicks].size, groups[:snares].size, groups[:hats].size].reject(&:zero?).min || 0
  puts "# Imported from #{File.basename(dir)} — pack-supplied MIDI, not transcription."
  (0...count).each do |i|
    k = groups[:kicks][i]&.last || { steps: [], ghosts: [] }
    s = groups[:snares][i]&.last || { steps: [], ghosts: [] }
    h = groups[:hats][i]&.last || { steps: [], ghosts: [] }
    o = groups[:open][i % [groups[:open].size, 1].max]&.last || { steps: [] }
    p = groups[:perc][i % [groups[:perc].size, 1].max]&.last || { steps: [] }
    puts "    #{slug}_#{i + 1}: {"
    puts "      swing: 52, humanize: 2, bpm: 140, mode: :straight_sixteenth,"
    puts "      kicks: #{k[:steps].inspect}, snares: #{s[:steps].inspect}, " \
         "hats: #{h[:steps].inspect},"
    puts "      ghosts: #{(s[:ghosts] + k[:ghosts]).uniq.sort.inspect}, " \
         "claps: #{s[:steps].inspect}, perc: #{(o[:steps] + p[:steps]).uniq.sort.inspect}"
    puts "    },"
  end
  count
end

# GM drum map note numbers (channel 9).
DRUM_MIDI_NOTES = {
  kick: 36, snare: 38, hat: 42, open: 46, clap: 39, perc: 37, ghost: 38
}.freeze

MIDI_SEED_DIR = File.join(ROOT, "samples", "midi").freeze

# Write a one-bar 16-step GM drum SMF for a single voice (kick/snare/hat…).
def write_drum_role_smf(path, steps, note:, velocity: 100, ghost_steps: [], ghost_vel: 48, bpm: 90)
  # Ticks per 16th at SMF_PPQN (quarter = SMF_PPQN): 16th = PPQN/4.
  step_ticks = SMF_PPQN / 4
  channel = 9 # GM drums
  events = []
  Array(steps).each do |st|
    on = st.to_i * step_ticks
    events << [on, :on, note, velocity]
    events << [on + (step_ticks / 2), :off, note, 0]
  end
  Array(ghost_steps).each do |st|
    next if Array(steps).include?(st)

    on = st.to_i * step_ticks
    events << [on, :on, note, ghost_vel]
    events << [on + (step_ticks / 3), :off, note, 0]
  end
  events.sort_by! { |t, kind, *| [t, kind == :off ? 0 : 1] }

  track_events = []
  last = 0
  events.each do |tick, kind, n, v|
    delta = [tick - last, 0].max
    status = kind == :on ? (0x90 | channel) : (0x80 | channel)
    track_events << [delta, [status, n, v].pack("C*")]
    last = tick
  end
  # pad to full bar
  bar_end = 16 * step_ticks
  track_events << [[bar_end - last, 0].max, [0xFF, 0x2F, 0x00].pack("C*")]
  track_data = track_events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, header + track_chunk)
  path
end

# Export every DRUM_PRESET as split kick/snare/hat MIDI clips under samples/midi/.
# Re-importable via `ruby dilla.rb import-midi samples/midi/<preset>`.
def export_midi_drums!(dest_dir = MIDI_SEED_DIR)
  FileUtils.mkdir_p(dest_dir)
  written = 0
  DillaLofiMachine::DRUM_PRESETS.each do |name, grid|
    preset_dir = File.join(dest_dir, name.to_s)
    FileUtils.mkdir_p(preset_dir)
    bpm = grid[:bpm] || 90
    write_drum_role_smf(File.join(preset_dir, "kick.mid"), grid[:kicks],
                        note: DRUM_MIDI_NOTES[:kick], velocity: 110, bpm:)
    write_drum_role_smf(File.join(preset_dir, "snare.mid"), grid[:snares],
                        note: DRUM_MIDI_NOTES[:snare], velocity: 108,
                        ghost_steps: grid[:ghosts], ghost_vel: 52, bpm:)
    write_drum_role_smf(File.join(preset_dir, "hat.mid"), grid[:hats],
                        note: DRUM_MIDI_NOTES[:hat], velocity: 88, bpm:)
    if Array(grid[:claps]).any?
      write_drum_role_smf(File.join(preset_dir, "clap.mid"), grid[:claps],
                          note: DRUM_MIDI_NOTES[:clap], velocity: 100, bpm:)
    end
    if Array(grid[:perc]).any?
      write_drum_role_smf(File.join(preset_dir, "perc.mid"), grid[:perc],
                          note: DRUM_MIDI_NOTES[:perc], velocity: 90, bpm:)
    end
    # Combined kit SMF (all voices on ch.10) for DAW drag-in.
    combo = File.join(preset_dir, "#{name}_kit.mid")
    write_combined_drum_smf(combo, grid)
    written += 1
  end
  puts "export-midi: #{written} presets → #{dest_dir}"
  written
end

def write_combined_drum_smf(path, grid)
  step_ticks = SMF_PPQN / 4
  channel = 9
  events = []
  {
    kicks: [DRUM_MIDI_NOTES[:kick], 110],
    snares: [DRUM_MIDI_NOTES[:snare], 108],
    hats: [DRUM_MIDI_NOTES[:hat], 88],
    claps: [DRUM_MIDI_NOTES[:clap], 100],
    perc: [DRUM_MIDI_NOTES[:perc], 90],
    ghosts: [DRUM_MIDI_NOTES[:ghost], 50],
  }.each do |role, (note, vel)|
    Array(grid[role]).each do |st|
      on = st.to_i * step_ticks
      events << [on, :on, note, vel]
      events << [on + (step_ticks / 2), :off, note, 0]
    end
  end
  events.sort_by! { |t, kind, *| [t, kind == :off ? 0 : 1] }
  track_events = []
  last = 0
  events.each do |tick, kind, n, v|
    delta = [tick - last, 0].max
    status = kind == :on ? (0x90 | channel) : (0x80 | channel)
    track_events << [delta, [status, n, v].pack("C*")]
    last = tick
  end
  bar_end = 16 * step_ticks
  track_events << [[bar_end - last, 0].max, [0xFF, 0x2F, 0x00].pack("C*")]
  track_data = track_events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, header + track_chunk)
  path
end

def build_crate!(dest_dir = CRATE_DIR)
  FileUtils.mkdir_p(dest_dir)
  made = []

  CRATE_CHORDS.each do |name, (root, quality)|
    freqs = chord_from_root(root, quality)
    CRATE_VOICES.each_key do |voice|
      expr, lp = crate_tonal_expr(freqs, voice)
      path = File.join(dest_dir, "#{voice}_#{name}.wav")
      begin
        # aevalsrc generates; the null source above is replaced for tonal voices.
        sh! "ffmpeg", "-y", "-f", "lavfi",
            "-i", "aevalsrc='#{expr}':d=4:s=#{SAMPLE_RATE}",
            "-af", "lowpass=f=#{lp},afade=t=out:st=3.6:d=0.4," \
                   "alimiter=limit=0.9:level_out=0.92",
            "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", path
        made << path
      rescue StandardError => e
        warn "crate #{voice}/#{name}: #{e.message}"
      end
    end
  end

  CRATE_TEXTURES.each do |name, filter|
    path = File.join(dest_dir, "texture_#{name}.wav")
    begin
      crate_render_one!(path, filter, 8.0)
      made << path
    rescue StandardError => e
      warn "crate #{name}: #{e.message}"
    end
  end

  CRATE_PERCUSSION.each do |name, filter|
    path = File.join(dest_dir, "perc_#{name}.wav")
    begin
      crate_render_one!(path, filter, 1.0)
      made << path
    rescue StandardError => e
      warn "crate #{name}: #{e.message}"
    end
  end

  puts "crate: #{made.size} files in #{dest_dir}"
  made
end
