# Audio references are explicitly separated from the regular Dilla showcase.
require "digest"
require "open3"
require "uri"

# ---------------------------------------------------------------------- CLI
def run(argv)
  return Dilla::Reference.run(argv.drop(1)) if argv.first == "reference"
  return Dilla::IndustrialTechno.run(argv.drop(1)) if argv.first == "industrial-techno"
  RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !RubyVM::YJIT.enabled? && !ENV.key?('DILLA_NO_YJIT') # about a third off every render
  live_argument = argv.first == 'live'
  argv = argv.drop(1) if live_argument
  options = {}
  OptionParser.new do |o|
    o.banner = 'Usage: ruby dilla.rb [options] | reference URL_OR_AUDIO | industrial-techno [options]'
    o.on('--showcase', 'Render the eight-part Blue Hour pure-tone composition to dilla.wav') { options[:showcase] = true }
    o.on('--live', 'Loop the showcase through the system audio player') { options[:live] = true }
    o.on('--list', 'List progressions, drum patterns and groove profiles') { options[:list] = true }
    o.on('--progression N', Integer, 'Progression index (see --list)') { |v| options[:prog] = v }
    o.on('--random', 'Random progression and drum pattern (the default groove profile)') { options[:random] = true }
    o.on('--drums NAME', 'Drum pattern name, or rotate to change the pattern every phrase') { |v| options[:drums] = v }
    o.on('--kit NAME', 'The drum kit (see kits in dilla.json)') { |v| options[:kit] = v }
    o.on('--profile NAME', 'Groove profile name') { |v| options[:profile] = v }
    o.on('--groove N', Float, 'pd_amount, 0 to 1.5: how far the profile pulls from the grid') { |v| options[:groove] = v }
    o.on('--bpm N', Float, 'Tempo (default 88)') { |v| options[:bpm] = v }
    o.on('--beats N', Float, 'Beats per chord (default 8, two bars)') { |v| options[:beats] = v }
    o.on('--gate N', Float, 'Note gate as a share of its step, 0.05 to 1.5') { |v| options[:gate] = v.clamp(0.05, 1.5) }
    o.on('--seed N', Integer, 'Seed: the same seed plays the same render') { |v| options[:seed] = v }
    o.on('--out PATH', 'Output WAV path') { |v| options[:out] = v }
    o.on('--midi PATH', 'Also write a Standard MIDI File') { |v| options[:midi] = v }
    o.on('--no-voice-search', 'Voice each chord by nearest tones only, without the octave search') { options[:plain] = true }
    o.on('--arp [PATTERN]', 'Play each chord one note at a time: up, down, updown, converge, spiral, pendulum, flow and more; --arp list names them') { |v| options[:arp] = v || true }
    o.on('--strum [MS]', Float, 'Stagger the notes of each chord, lowest first, by MS milliseconds (default from the data)') { |v| options[:strum] = v || true }
    o.on('--pad', 'A soft sustained pad under the arpeggio') { options[:pad] = true }
    o.on('--echo [HEADS]', 'Tape space echo; heads such as 1 or 1,2 or 1,2,3') { |v| options[:echo] = v || true }
    o.on('--echo-mix N', Float, 'Echo volume against the dry sound') { |v| options[:echo_mix] = v }
    o.on('--echo-feedback N', Float, 'Echo intensity, 0 to 0.9: how much of each repeat comes round again') { |v| options[:echo_feedback] = v }
    o.on('--echo-time MS', Float, 'Echo base delay in milliseconds (default a dotted eighth)') { |v| options[:echo_time] = v }
    o.on('--play', '--endless', 'Never stop: stream pass after pass into the player, each beginning under the last beat of the one before') { options[:play] = true }
    o.on('--player CMD', 'The player: for live it is given the wav path (default afplay, else ffplay); for --play it reads raw 16-bit mono PCM on stdin (default ffplay, else sox play)') { |v| options[:player] = v }
    o.on('--decks N', Integer, 'With --play: 2 decks cross over eight to sixteen bars (the default), 1 plays pass after pass under a one-beat crossfade') { |v| options[:decks] = v.clamp(1, 2) }
    o.on('--moves N', Float, 'With --play: live moves a minute on average, 0 for none (default 3 with two decks)') { |v| options[:moves] = v }
    o.on('--passes N', Integer, 'With --play, stop after N progressions') { |v| options[:passes] = v }
    o.on('--voice NAME', 'The voice that plays the notes (see data/dilla.json): pure_tone, sine, moog_*, rhodes_*, dfam') { |v| options[:voice] = v }
    o.on('--repeat [STYLE]', '--comp [STYLE]', 'Strike the whole chord again on the steps of a style instead of arpeggiating') { |v| options[:repeat] = v || true }
    o.on('--patch-per-chord', 'In pad mode, give every chord its own patch, drawn from the one bag of all patches') { options[:patch_per_chord] = true }
    o.on('--mode MODE', 'arp, repeat, pad or organ: force how the chords are played') { |v| options[:mode] = v }
    o.on('--key NAME', 'With --mode organ: the tonic, such as D or Bb (else drawn from the seed)') { |v| options[:key] = v }
    o.on('--scale NAME', 'With --mode organ: harmonic_minor, natural_minor, major or dorian (else drawn from the seed)') { |v| options[:scale] = v }
    o.on('--bars N', Integer, 'With --mode organ: bars of improvisation, one chord a bar (default from the data)') { |v| options[:bars] = v }
    o.on('--arp-rate N', 'Sixteenths per arp note: 2 eighth, 3 dotted eighth, 4 quarter, 6, 8; 3T for triplets') { |v| options[:arp_rate] = v }
    o.on('--arp-style NAME', 'A row of arp.styles in data/dilla.json') { |v| options[:arp_style] = v }
    o.on('--lufs N', Float, 'Integrated loudness the master brings the sound to (default -14)') { |v| options[:lufs] = v.clamp(-40.0, -3.0) }
    o.on('--no-master', 'Leave out the mixing and mastering chain: no EQ, multiband, glue, loudness or true-peak limiter') { options[:master] = false }
    o.on('--bits N', Integer, 'Bit depth of a written wav, 16 (dithered) or 24') { |v| options[:bits] = v == 24 ? 24 : 16 }
    o.on('--mono', 'One channel, with no panning, no ping-pong echo and no stereo imager (the default is stereo)') { options[:mono] = true }
    o.on('--tape N', Integer, 'Tape machines in series as the last stage, 0 to 8; 0 leaves the sound untouched (default from the data)') { |v| options[:tape] = v.clamp(0, 8) }
    o.on('--tape-drive X', Float, 'How hard the first tape machine is driven, 0.1 to 4; later machines step up from it') { |v| options[:tape_drive] = v.clamp(0.1, 4.0) }
    o.on('--sonitex [PRESET]', 'The 12-bit sampler colour chain on the voice bus') { |v| options[:sonitex] = v || true }
    o.on('--sonitex-instances N', Integer, 'Run it 1 to 3 times: one is a colour, three are a sound') { |v| options[:sonitex_instances] = v }
    o.on('--drum-tape LEVEL', %w[light medium heavy], 'Analogue tape saturation on the drum bus') { |v| options[:drum_tape] = v }
    o.on('--vcs [AMOUNT]', Float, 'The summing colour, 0 to 1, on each bus and the master') { |v| options[:vcs] = v || true }
    o.on('--transpose N', Integer, 'Move every note N semitones before synthesis; tempo and echo timing stay') { |v| options[:transpose] = v }
    o.on('--octaves N', Integer, 'Sugar for --transpose 12*N') { |v| options[:transpose] = 12 * v }
    o.on('--transpose-wrap', 'Fold any note still above 14 kHz down by octaves') { options[:wrap] = true }
    o.on('--kick-db N', Float, 'Kick level in dB (default from the data)') { |v| (options[:mix] ||= {})['kick'] = v }
    o.on('--snare-db N', Float, 'Snare and clap level in dB') { |v| (options[:mix] ||= {}).merge!('snare' => v, 'clap' => v) }
    o.on('--hat-db N', Float, 'Hat level in dB') { |v| (options[:mix] ||= {})['hat'] = v }
    o.on('--chords-db N', Float, 'Chord and arp level in dB when drums play') { |v| (options[:mix] ||= {})['chords'] = v }
    o.on('--pool POOL', %w[essential all], 'With --play: essential progressions (default) or all') { |v| options[:pool] = v }
    o.on('--quick', 'Render the first progression as a smoke test') { options[:quick] = true }
  end.parse!(argv)
  options[:live] = true if live_argument

  data = JSON.parse(File.read(File.expand_path('../../data/dilla.json', __dir__)))
progressions = data.fetch('progressions')

if options[:arp] == 'list'
  puts "Arp patterns: #{data.dig('arp', 'patterns').join(', ')}"
  puts "Arp styles: #{data.dig('arp', 'styles').keys.join(', ')}"
  puts "Arp modifiers: #{(data.fetch('arp').keys & %w[euclidean probability note_repeat ratchet humanize grace]).join(', ')}"
elsif options[:play]
    play_forever(data, options)
  elsif options[:live]
    play_showcase(data, options)
  elsif options[:list]
    puts 'Progressions:'
    progressions.each_with_index { |chords, i| puts format('%4d  %s', i, chords.join(' ')) }
    puts
    puts "Drum patterns: #{data['drum_patterns'].keys.join(', ')}"
    puts "Groove profiles: #{data['groove_profiles'].keys.join(', ')}"
  elsif options[:showcase] || (options[:prog].nil? && !options[:random] && !options[:quick] && options[:mode] != 'organ')
    render_showcase(data, options)
  else
    render(data, options)
  end
end

# How the chords are played: the flags, else what the profile carries, else a held pad.
def play_mode(options, seq)
  return options[:mode] if options[:mode]
  return 'repeat' if options[:repeat] || (!options[:arp] && seq.comp_settings(nil))
  return 'arp' if options[:arp] || options[:arp_style] || seq.arp_settings(nil)

  'pad'
end

def parse_rate(text)
  return nil unless text

  text.to_s.match(/\A(\d+(?:\.\d+)?)(T?)\z/) or abort "Bad --arp-rate: #{text}"
  Regexp.last_match(2).empty? ? Regexp.last_match(1).to_f : Regexp.last_match(1).to_f * 2 / 3
end

# Everything about a pass except the processing after the parts: the progression, the sequencer,
# the tempo, and the source part of the sound. With `capture` the parts are not synthesised but
# kept as notes with their voices, for the streamer to play block by block.
Plan = Struct.new(:index, :names, :profile, :profile_row, :drums, :seq, :bpm, :beats, :voice, :mode, :search, :piece,
                  :chord_voices, :seed, :buf, :parts, :pick, keyword_init: true)

def plan_pass(data, options, capture: false)
  progressions = data.fetch('progressions')
  seed = options[:seed] || Random.new_seed % 1_000_000
  pick = Random.new(seed)
  index = options[:section_index] || (options[:quick] ? 0 : (options[:prog] || pick.rand(progressions.size)))
  names = options[:names] || progressions.fetch(index) { abort "No progression: #{index}" }
  profile = options[:profile] || data.fetch('default_profile')
  profile_row = data['groove_profiles'].fetch(profile) { abort "No groove profile: #{profile}" }
  drums = options[:drums] || profile_row['drums'] || (options[:random] ? data['drum_patterns'].keys.sample(random: pick) : nil)

  seq = Sequencer.new(data, profile_name: profile, pd_amount: options[:groove], seed: seed,
                            transpose: options[:transpose] || 0, wrap: options[:wrap], kit: options[:kit])
  seq.capture = [] if capture
  bpm = options[:bpm] || seq.bpm
  seq.tempo = bpm
  beats = options[:beats] || seq.beats
  voice = seq.voice_spec(options[:voice])
  search = !options[:plain]
  mode = play_mode(options, seq)
  validate_scale!(names, options[:melody], options[:scale_pcs]) if options[:scale_pcs]
  warn_past_nyquist(names, search, options)
  chord_voices = piece = nil
  buf =
    case mode
    when 'arp'
      arp = seq.arp_settings(options[:arp] || true, style: options[:arp_style], rate: parse_rate(options[:arp_rate]))
      arp['gate'] = options[:gate] if options[:gate]
      seq.render_arp(names, bpm, beats, arp, search:, pad: options[:pad], voice:)
    when 'organ'
      piece = Organ.compose(seed:, config: data.fetch('organ'), bars: options[:bars], key: options[:key], scale: options[:scale])
      names = piece.names
      beats = 4.0
      seq.render_organ(piece, bpm, seq.voice_spec('organ'))
    when 'repeat'
      comp = seq.comp_settings(options[:repeat] || true)
      comp['gate'] = options[:gate] if options[:gate]
      seq.render_repeat(names, bpm, beats, comp, search:, voice:)
    else
      chord_voices = options[:chord_voices] || (options[:patch_per_chord] ? Playlist.new(data, Random.new(seed)).voices_for(names.size) : nil)
      seq.render_chords(names, bpm, beats, search:, strum: seq.strum(options[:strum]), voice:,
                        voices: chord_voices && seq.voice_specs(chord_voices))
    end
  if options[:melody]
    beat_seconds = 60.0 / bpm
    plucks = options[:melody].map do |beat, midi, length, gain|
      Pluck.new(beat.to_f * beat_seconds, 0.0, midi.to_i, length.to_f * beat_seconds, gain.to_f)
    end
    seq.sound(buf, plucks, seq.voice_spec(options[:melody_voice] || 'rhodes_mark1'))
  end
  render_layers(buf, seq, names, bpm, beats, options, search:)
  Plan.new(index:, names:, profile:, profile_row:, drums:, seq:, bpm:, beats:, voice:, mode:, search:, piece:, chord_voices:, seed:, buf:,
           parts: seq.capture, pick:)
end

# A section of the showcase: one pass rendered whole and mono by the functional effects, kept
# in memory for the arrangement to join. Every other render is streamed (see render_stream).
def render_section(data, options)
  plan = plan_pass(data, options)
  names, profile, drums, seq, bpm, beats, buf = plan.to_h.values_at(:names, :profile, :drums, :seq, :bpm, :beats, :buf)
  # Progression buffers reserve a full second for arbitrary note tails. A curated section
  # has a known gate and a short echo, so discard that unused second before rendering drums.
  musical_samples = (names.size * beats * 60.0 / bpm * SAMPLE_RATE).round
  buf = buf.first([musical_samples + (0.36 * SAMPLE_RATE).round, buf.size].min)
  vcs = seq.vcs_amount(options[:vcs])
  sonitex = seq.sonitex_settings(options[:sonitex], instances: options[:sonitex_instances])
  drum_sonitex = seq.sonitex_settings(options[:drum_sonitex], instances: options[:drum_sonitex_instances]) || sonitex
  buf = seq.colour(buf, sonitex, vcs)
  echo = seq.echo_settings(flag: options[:echo], mix: options[:echo_mix], feedback: options[:echo_feedback], time_ms: options[:echo_time])
  echo['tail'] = options[:echo_tail] if echo && options[:echo_tail]
  echo['reverb'] = options[:echo_reverb] unless !echo || options[:echo_reverb].nil?
  buf = seq.echo(buf, echo, bpm, resets: (1...names.size).map { |i| (i * beats * 60.0 / bpm * SAMPLE_RATE).round }) if echo
  buf = FX.dub_echo(buf, options[:instrument_dub_echo]) if options[:instrument_dub_echo]
  buf = FX.crystallizer(buf, options[:instrument_crystallizer]) if options[:instrument_crystallizer]
  drum_seconds = names.size * beats * 60.0 / bpm
  rotation = drums == 'rotate' ? data.fetch('drum_patterns').keys : drums
  hits = drums ? seq.drum_hits(rotation, bpm, drum_seconds) : []
  levels = seq.mix(options[:mix])
  buf = seq.scale(buf, levels.fetch('chords')) unless hits.empty?
  buf = seq.duck(buf, hits)
  buf = FX.apply(buf, data['groove_profiles'].fetch(profile))
  buf = seq.overlay_drums(
    buf, hits, levels, vcs,
    sonitex: drum_sonitex,
    tape: options[:drum_tape],
    dub_echo: options[:drum_dub_echo],
    crystallizer: options[:drum_crystallizer],
    drum_vcs: options[:drum_vcs]
  ) if drums
  buf
end

# One render, streamed whole: the pass is run through the same streamer as --play, a bar at a
# time, then the master stage, and written as a stereo wav (or mono with --mono). Returns the path.
def render_stream(data, options)
  streamer = Streamer.new(data, options, ring: true)
  plan = streamer.plan
  frame = Stereo.zeros(streamer.channels, 0)
  bar = streamer.beat * 4
  until streamer.finished?
    part = streamer.next_block(bar)
    Stereo.concat!(frame, streamer.channels == 1 ? [part] : part)
  end
  tape = data.fetch('tape')
  instances = options.fetch(:tape, tape.fetch('instances'))
  args = { drive: options[:tape_drive] || tape.fetch('drive'), config: tape }
  # the stack is level matched against the programme itself, which a whole render has to hand
  stack = instances.positive? ? ->(sample) { Tape::Stack.new(instances:, seed: plan.seed, sample:, **args) } : nil
  chain = options[:master] == false ? nil : Mastering::Chain.new(data.fetch('master'), channels: streamer.channels, bpm: plan.bpm, whole: true)
  chain&.target = options[:lufs] if options[:lufs]
  master = Moves::Master.new(tape: stack, ceiling: tape.fetch('ceiling', 0.97), preset: nil, seed: plan.seed, instances:, tape_args: args,
                             imager: options[:mono] ? nil : data.dig('stereo', 'imager'), chain:)
  frame = master.process(frame)
  if (tail = master.flush)
    frame = frame.each_with_index.map { |channel, c| channel.drop(chain.latency) + tail[c].first(chain.latency) } # the limiter's delay taken out
  end
  bits = options.fetch(:bits, 16)
  frame = Mastering::Dither.new(plan.seed).process(frame) if chain && bits == 16
  report = Mastering.report(frame) if chain
  out = options[:out] || (options[:quick] ? 'out/quick.wav' : "out/progression_#{plan.index}#{plan.drums ? "_#{Array(plan.drums).join('+')}" : ''}.wav")
  FileUtils.mkdir_p(File.dirname(out))
  WAV.write(out, streamer.channels == 1 ? frame.first : frame, bits:)
  if options[:midi]
    FileUtils.mkdir_p(File.dirname(options[:midi]))
    MIDI.write(options[:midi], plan.names, plan.bpm, plan.beats, streamer.hits, search: plan.search)
  end
  piece = plan.piece
  label = piece ? "organ in #{piece.key} #{piece.scale}, #{piece.phrases.size} phrases, #{piece.suspensions} suspensions" : "progression #{plan.index}"
  puts "Wrote #{out} (#{(frame.first.size / SAMPLE_RATE.to_f).round(2)}s, #{streamer.channels == 1 ? 'mono' : 'stereo'}) #{label}: #{plan.names.join(' ')}"
  puts "  drums=#{plan.drums ? Array(plan.drums).join(',') : 'none'} profile=#{plan.profile} mode=#{plan.mode} " \
       "voice=#{piece ? 'organ' : (plan.chord_voices&.join('>') || plan.voice['name'])} groove=#{plan.seq.pd_amount} bpm=#{plan.bpm} tape=#{instances} seed=#{plan.seed}"
  puts Mastering.report_line(report) if report
  out
end

# A render: a showcase section stays whole and mono in memory, anything else is streamed.
def render(data, options) = options[:buffer_only] ? render_section(data, options) : render_stream(data, options)

# The last colour before the file: the tape stack, and the ceiling that follows it.
def tape_stage(buf, data, options, seed)
  config = data.fetch('tape')
  Tape.apply(buf, instances: options.fetch(:tape, config.fetch('instances')), drive: options[:tape_drive] || config.fetch('drive'), seed:, config:)
end

# Reject a line whose notes drift out of the arrangement's named scale.
# This keeps every added layer tied to the same harmonic source.
def validate_scale!(names, melody, scale_pcs)
  allowed = scale_pcs.map(&:to_i).uniq
  chord_pcs = names.flat_map do |name|
    chord = Chords.parse(name)
    (chord[:tones].map { |tone| (chord[:pc] + tone) % 12 } + [chord[:bass]].compact).uniq
  end.uniq
  chord_outside = chord_pcs - allowed
  melody_outside = Array(melody).filter_map do |event|
    midi = event[1].to_i
    midi % 12 unless allowed.include?(midi % 12)
  end.uniq
  return if chord_outside.empty? && melody_outside.empty?

  abort "Scale mismatch: chord pitch classes #{chord_outside.inspect}, melody pitch classes #{melody_outside.inspect}, allowed #{allowed.inspect}"
end

# `count` notes of a chord, the lowest and the highest and the ones between spaced evenly: a thin
# layer that still spans the voicing.
def spread(notes, count)
  return notes if count >= notes.size

  Array.new(count) { |i| notes[(i * (notes.size - 1) / [count - 1, 1].max.to_f).round] }.uniq
end

# Add deliberate layers behind and above the main instrument part without modulation effects.
# Held layers use the very same chord voicings; patterned layers share the same tempo and groove.
def render_layers(buf, seq, names, bpm, beats, options, search:)
  Array(options.fetch(:layers) { seq.profile_layers }).each do |layer|
    voice = seq.voice_spec(layer.fetch('voice'))
    gate = layer.fetch('gate', 0.9).to_f.clamp(0.05, 1.5)
    mode = layer.fetch('mode', 'held')
    layer_buf = nil
    seq.with_part(gain: 10.0**(layer.fetch('gain_db', -12.0).to_f / 20.0)) do
    layer_buf =
      case mode
      when 'held'
        layer_buffer = Array.new(buf.size, 0.0)
        beat_seconds = 60.0 / bpm
        chords = Chords.midi_notes(names, search:, transpose: (options[:transpose] || 0) + layer.fetch('transpose', 0).to_i, wrap: options[:wrap])
        chords = chords.map { |notes| notes.first(1) } if layer['notes'] == 'bass'
        chords = chords.map { |notes| spread(notes, layer['count']) } if layer['count']
        plucks = chords.each_with_index.map do |notes, index|
          Pluck.new(index * beats * beat_seconds, 0.0, notes, beats * beat_seconds * gate,
                    layer.fetch('velocity', 0.55).to_f.clamp(0.0, 1.0))
        end
        seq.sound(layer_buffer, plucks, voice)
        layer_buffer
      when 'repeat'
        style = layer.fetch('pattern', 'half_note_pulse')
        comp = seq.comp_settings(style).merge('gate' => gate, 'modifiers' => [])
        seq.render_repeat(names, bpm, beats, comp, search:, voice:)
      when 'arp'
        pattern = layer.fetch('pattern', 'updown')
        arp = seq.arp_settings(pattern, rate: layer.fetch('rate', 4).to_f)
        arp['gate'] = gate
        arp['octaves'] = layer.fetch('octaves', 1).to_i.clamp(1, 2)
        arp['modifiers'] = []
        shift = layer.fetch('transpose', 0).to_i
        if shift.zero?
          seq.render_arp(names, bpm, beats, arp, search:, voice:)
        else
          chord_events = seq.note_events(names, bpm, beats, arp, 'arp', search:)
          chord_events.each do |plucks|
            plucks.each do |pluck|
              pluck.midi = Array(pluck.midi).map { |midi| midi + shift }.then { |notes| pluck.midi.is_a?(Array) ? notes : notes.first }
            end
          end
          layer_buffer = Array.new(buf.size, 0.0)
          chord_events.each { |plucks| seq.sound(layer_buffer, plucks, voice) }
          layer_buffer
        end
      else
        abort "Unknown synth layer mode: #{mode}"
      end
    end

    next if seq.capture

    gain = 10.0**(layer.fetch('gain_db', -12.0).to_f / 20.0)
    layer_buf.each_with_index do |sample, index|
      buf[index] += sample * gain if index < buf.size
    end
  end
  buf
end

# Render the curated arrangement from the same patches, chord voicer, sequencer, effects,
# and drum synthesiser used by ordinary progression renders.
def render_showcase(data, options)
  arrangement = JSON.parse(File.read(File.expand_path('../../data/showcase.json', __dir__)))
  sections = arrangement.fetch('sections')
  seed = options[:seed] || 261_013
  crossfade = (arrangement.fetch('crossfade_seconds', 0.18) * SAMPLE_RATE).round
  combined = []

  sections.each_with_index do |section, index|
    effect_rig = data.fetch('bus_effects').fetch(section.fetch('effect_rig'))
    mode = options[:mode] || ((options[:arp] || options[:arp_style] || options[:arp_rate]) ? 'arp' : (options[:repeat] ? 'repeat' : section.fetch('mode', 'repeat')))
    section_options = {
      names: section.fetch('progression'),
      section_index: index,
      bpm: options[:bpm] || section.fetch('bpm'),
      beats: options[:beats] || section.fetch('beats_per_chord', 2.0),
      gate: options[:gate] || section.fetch('gate', 0.88),
      voice: options[:voice] || section.fetch('voice'),
      mode:,
      repeat: options[:repeat].is_a?(String) ? options[:repeat] : section.fetch('repeat', 'half_note_pulse'),
      arp: options[:arp] || (mode == 'arp' ? true : nil),
      arp_style: options[:arp_style],
      arp_rate: options[:arp_rate],
      pad: options[:pad],
      strum: options[:strum],
      profile: options[:profile] || section.fetch('profile', 'soft_swing'),
      drums: options[:drums] || section.fetch('drums'),
      echo: options[:echo] || section.fetch('echo', false),
      echo_mix: options[:echo_mix] || section['echo_mix'],
      echo_feedback: options[:echo_feedback] || section['echo_feedback'],
      echo_time: options[:echo_time] || section['echo_time_ms'],
      echo_tail: section['echo_tail_seconds'],
      echo_reverb: section['echo_reverb'],
      mix: section.fetch('mix', {}).merge(options[:mix] || {}),
      scale_pcs: section['scale_pcs'],
      melody: section['melody'],
      melody_voice: section['melody_voice'],
      layers: section['layers'],
      drum_sonitex: options[:drum_sonitex] || effect_rig.fetch('drum_sonitex'),
      drum_sonitex_instances: options[:drum_sonitex_instances] || effect_rig.fetch('drum_sonitex_instances'),
      drum_tape: options[:drum_tape] || effect_rig.fetch('drum_tape'),
      drum_vcs: effect_rig.fetch('drum_vcs'),
      drum_dub_echo: effect_rig.fetch('drum_dub_echo'),
      drum_crystallizer: effect_rig.fetch('drum_crystallizer'),
      instrument_dub_echo: effect_rig.fetch('instrument_dub_echo'),
      instrument_crystallizer: effect_rig.fetch('instrument_crystallizer'),
      seed: seed + (index * 97),
      groove: options[:groove],
      transpose: options[:transpose],
      wrap: options[:wrap],
      plain: options[:plain],
      sonitex: options[:sonitex] || section['sonitex'],
      sonitex_instances: options[:sonitex_instances] || section['sonitex_instances'],
      vcs: options[:vcs].nil? ? section['vcs'] : options[:vcs],
      buffer_only: true
    }.reject { |_key, value| value.nil? }

    part = render(data, section_options)
    if combined.empty?
      combined = part
    else
      overlap = [crossfade, combined.size, part.size].min
      left = combined.pop(overlap)
      overlap.times do |i|
        phase = overlap <= 1 ? 1.0 : i.to_f / (overlap - 1)
        combined << (left[i] * (1.0 - phase)) + (part[i] * phase)
      end
      combined.concat(part.drop(overlap))
    end
    puts format('section %d/%d: %s — %d BPM, %s', index + 1, sections.size,
                section.fetch('name'), section.fetch('bpm'), section.fetch('voice'))
  end

  combined = tape_stage(combined, data, options, seed)
  fade = [SAMPLE_RATE / 25, combined.size / 2].min
  fade.times do |i|
    combined[i] *= i.to_f / [fade, 1].max
    combined[-fade + i] *= (fade - i - 1).to_f / [fade, 1].max
  end
  peak = combined.map(&:abs).max || 0.0
  combined.map! { |sample| sample * (0.92 / peak) } if peak > 0.92

  out = options[:out] || File.expand_path('../../dilla.wav', __dir__)
  FileUtils.mkdir_p(File.dirname(out))
  WAV.write(out, combined)
  puts format('Wrote %s (%.2fs, 44.1 kHz mono) — %s', out, combined.size / SAMPLE_RATE.to_f,
              arrangement.fetch('title'))
  puts "  seed=#{seed}; sections=#{sections.size}; peak=#{format('%.3f', combined.map(&:abs).max || 0.0)}"
  out
end

# Live mode loops the same approved arrangement instead of switching to unrelated progressions.
def play_showcase(data, options)
  path = render_showcase(data, options)
  command = player_command(options)
  passes = 0
  loop do
    pid = Process.spawn(*command, path)
    _waited, status = Process.wait2(pid)
    unless status.success?
      warn "player exited with status #{status.exitstatus}"
      break
    end
    passes += 1
    break if options[:passes] && passes >= options[:passes]
  end
end

# A transposed note above the sample rate's limit cannot be played; say so rather than fake it.
def warn_past_nyquist(names, search, options)
  return unless options[:transpose]&.nonzero?

  notes = Chords.midi_notes(names, search:, transpose: options[:transpose], wrap: options[:wrap]).flatten
  over = notes.count { |n| !Voices.audible?(Chords.hz(n)) }
  return if over.zero?

  warn format('warning: %<over>d of %<all>d notes are above %<limit>d Hz and are dropped (silence); --transpose-wrap folds them down',
              over:, all: notes.size, limit: SAMPLE_RATE * NYQUIST_SHARE)
end

# The player command for a wav: --player, else afplay on a Mac, else ffplay.
def player_command(options)
  return Shellwords.split(options[:player]) if options[:player]

  RUBY_PLATFORM.include?('darwin') ? ['afplay'] : %w[ffplay -nodisp -autoexit -loglevel quiet]
end

# Never stops: each pass is drawn from the bags and streamed into the player, one beginning under
# the last beat of the one before. The bags are saved beside the output folder, so a restart
# goes on with the cycle. The player reads raw 16-bit mono PCM on stdin.
def play_forever(data, options)
  player = Player.new(Player.command(options))
  show = Show.new(data, options, player:)
  %w[INT TERM].each { |signal| trap(signal) { show.stop! } }
  show.run
  stats = show.stats
  puts format('played %<audio>.1fs of audio, rendered in %<render>.1fs (%<ratio>.2fx real time), %<under>d late blocks',
              audio: stats[:audio], render: stats[:render], ratio: stats[:render] / [stats[:audio], 1e-9].max, under: stats[:underruns])
end

run(ARGV) if $PROGRAM_NAME == __FILE__


# Import and inspect the audio stream of a reference. Video frames are never read.
module Dilla
  module Reference
    ROOT = File.expand_path("../../..", __dir__).freeze
    REFERENCE_ROOT = File.join(ENV.fetch("XDG_DATA_HOME", File.expand_path("~/Documents")), "dilla-references").freeze
    MAX_DURATION = 7_200
    DEFAULT_DURATION = 900
    VIDEO_ID = /\A[A-Za-z0-9_-]{11}\z/.freeze
    class Error < StandardError; end
    module_function

    def run(argv)
      options = { stems: true, model: "htdemucs", max_duration: DEFAULT_DURATION }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby dilla.rb reference YOUTUBE_URL_OR_AUDIO [options]"
        parser.on("--out DIR") { |value| options[:out] = value }
        parser.on("--no-stems") { options[:stems] = false }
        parser.on("--model NAME") { |value| options[:model] = value }
        parser.on("--max-duration SECONDS", Integer) do |value|
          raise OptionParser::InvalidArgument, "duration must be 1..#{MAX_DURATION}" unless value.between?(1, MAX_DURATION)
          options[:max_duration] = value
        end
        parser.on("-h", "--help") { puts parser; return 0 }
      end.parse!(argv)
      source = argv.shift
      raise Error, "provide one YouTube video URL or a local audio file" if source.to_s.empty?
      raise Error, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      source.start_with?("http://", "https://") ? download_audio(source, options) : analyze(File.expand_path(source), nil, options)
    rescue OptionParser::ParseError, Error => error
      warn "reference0: #{error.message}"
      2
    rescue StandardError => error
      warn "reference0: failed safely (#{error.class}: #{error.message})"
      1
    end

    def parse_url(value)
      uri = URI.parse(value)
      raise Error, "only direct YouTube URLs are supported" unless %w[http https].include?(uri.scheme)
      host = uri.host.to_s.downcase
      parts = uri.path.to_s.split("/").reject(&:empty?)
      id = if %w[youtu.be www.youtu.be].include?(host)
             parts.first
           elsif %w[youtube.com www.youtube.com m.youtube.com music.youtube.com].include?(host)
             parts == ["watch"] ? URI.decode_www_form(uri.query.to_s).to_h["v"] : (parts[1] if %w[shorts embed live v].include?(parts.first))
           end
      raise Error, "expected a single YouTube video URL" unless VIDEO_ID.match?(id.to_s)
      { id: id, url: "https://www.youtube.com/watch?v=#{id}" }
    rescue URI::InvalidURIError, ArgumentError => error
      raise Error, "invalid YouTube URL: #{error.message}"
    end

    def download_audio(url, options)
      video = parse_url(url)
      ytdlp = executable("YT_DLP_BIN", "yt-dlp") or raise Error, "yt-dlp unavailable"
      out, = capture!("yt-dlp metadata", ytdlp, "--no-playlist", "--skip-download", "--dump-single-json", video[:url])
      metadata = JSON.parse(out)
      seconds = metadata["duration"].to_f
      raise Error, "source exceeds #{options[:max_duration]}s" if seconds.positive? && seconds > options[:max_duration]
      dir = options[:out] ? File.expand_path(options[:out]) : File.join(REFERENCE_ROOT, "#{video[:id]}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
      prepare_dir(dir)
      File.write(File.join(dir, "metadata.json"), JSON.pretty_generate({
        "source_type" => "youtube_audio", "id" => video[:id], "title" => metadata["title"],
        "channel" => metadata["channel"] || metadata["uploader"], "url" => video[:url],
        "duration_seconds" => seconds, "license" => metadata["license"]
      }.compact) + "\n")
      capture!("yt-dlp audio-only download", ytdlp, "--no-playlist", "--no-overwrites", "-f", "bestaudio/best",
               "-x", "--audio-format", "wav", "-o", File.join(dir, "source.%(ext)s"), video[:url],
               timeout: [[seconds.ceil + 300, 900].max, 57_600].min)
      audio = File.join(dir, "source.wav")
      raise Error, "download did not produce source.wav" unless File.file?(audio)
      analyze(audio, dir, options)
    end

    def analyze(audio, directory = nil, options = {})
      raise Error, "audio file does not exist: #{audio}" unless File.file?(audio) && File.readable?(audio)
      options = { stems: true, model: "htdemucs", max_duration: DEFAULT_DURATION }.merge(options)
      ffmpeg = executable("FFMPEG_BIN", "ffmpeg") or raise Error, "ffmpeg unavailable"
      ffprobe = executable("FFPROBE_BIN", "ffprobe") or raise Error, "ffprobe unavailable"
      duration = probe_duration(audio, ffprobe)
      raise Error, "source exceeds #{options[:max_duration]}s" if duration && duration > options[:max_duration]
      unless directory
        digest = Digest::SHA256.file(audio).hexdigest[0, 10]
        directory = options[:out] ? File.expand_path(options[:out]) :
          File.join(REFERENCE_ROOT, "#{File.basename(audio, File.extname(audio))}-#{digest}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
        prepare_dir(directory)
      end
      puts "reference0: analyzing audio only"
      mix = metrics(audio, ffmpeg:, ffprobe:, max_duration: options[:max_duration], bands: true)
      stems, separation = separate(audio, directory, options, duration)
      tracks = { "mix" => mix }
      stems.each do |path|
        tracks[File.basename(path, ".wav")] = metrics(path, ffmpeg:, ffprobe:, max_duration: options[:max_duration], bands: false)
      end
      mix["tempo"] = tempo(audio, ffmpeg:, max_duration: options[:max_duration])
      profile = profile_for(mix)
      report = { "schema_version" => 1, "tracks" => tracks, "separation" => separation,
                 "essentia" => essentia(audio, directory), "production_profile" => profile,
                 "limitations" => ["Tempo is estimated; half-time and double-time can both fit.",
                                   "Demucs stems can bleed and are not discrete kick/snare/hat multitracks.",
                                   "Spectral levels describe the mix, not isolated instruments.",
                                   "Only broad production traits guide new music; source audio and composition are not copied."] }
      File.write(File.join(directory, "analysis.json"), JSON.pretty_generate(report) + "\n")
      File.write(File.join(directory, "profile.json"), JSON.pretty_generate(profile) + "\n")
      FileUtils.mkdir_p(REFERENCE_ROOT)
      File.write(File.join(REFERENCE_ROOT, "latest_profile.json"), JSON.pretty_generate(profile) + "\n")
      write_report(File.join(directory, "report.md"), tracks, separation, profile)
      puts "reference0: separation=#{separation['status']}; analyzed #{tracks.size - 1} stems"
      puts "reference0: estimated tempo=#{mix.dig('tempo', 'bpm') || 'unknown'} BPM"
      puts "reference0: report=#{File.join(directory, 'report.md')}"
      0
    end

    def prepare_dir(path)
      raise Error, "refusing non-empty output directory: #{path}" if Dir.exist?(path) && !Dir.empty?(path)
      FileUtils.mkdir_p(path)
    end

    def metrics(path, ffmpeg:, ffprobe:, max_duration:, bands:)
      out, = capture!("ffprobe", ffprobe, "-v", "error", "-show_format", "-show_streams", "-of", "json", path)
      probe = JSON.parse(out)
      fmt = probe["format"] || {}
      stream = (probe["streams"] || []).find { |row| row["codec_type"] == "audio" } || {}
      _stdout, logs = capture!("FFmpeg audio stats", ffmpeg, "-hide_banner", "-nostats", "-i", path,
                               "-t", max_duration.to_s, "-af", "astats=metadata=0:reset=0,ebur128=peak=true", "-f", "null", "-")
      result = { "duration_seconds" => fmt["duration"]&.to_f, "codec" => stream["codec_name"],
                 "sample_rate_hz" => stream["sample_rate"]&.to_i, "channels" => stream["channels"]&.to_i,
                 "rms_db" => number(logs, /RMS level dB:\s*(-?[\d.]+)/),
                 "peak_db" => number(logs, /Peak level dB:\s*(-?[\d.]+)/),
                 "integrated_lufs" => number(logs, /I:\s*(-?[\d.]+)\s+LUFS/) }.compact
      result["spectral_bands_db"] = band_levels(path, ffmpeg:, max_duration:) if bands
      result
    end

    def band_levels(path, ffmpeg:, max_duration:)
      filters = { "sub_25_120_hz" => "highpass=f=25,lowpass=f=120,volumedetect",
                  "low_mid_120_500_hz" => "highpass=f=120,lowpass=f=500,volumedetect",
                  "mid_500_4000_hz" => "highpass=f=500,lowpass=f=4000,volumedetect",
                  "high_4000_plus_hz" => "highpass=f=4000,volumedetect" }
      filters.to_h do |name, filter|
        _out, logs = capture!("FFmpeg #{name}", ffmpeg, "-hide_banner", "-nostats", "-i", path,
                              "-t", max_duration.to_s, "-af", filter, "-f", "null", "-")
        [name, number(logs, /mean_volume:\s*(-?[\d.]+)\s+dB/)]
      rescue Error
        [name, nil]
      end
    end

    def tempo(path, ffmpeg:, max_duration:)
      bytes, = capture!("tempo envelope", ffmpeg, "-hide_banner", "-v", "error", "-i", path,
                        "-t", max_duration.to_s, "-vn", "-ac", "1", "-af",
                        "aeval=exprs=val(0)*val(0),lowpass=f=12", "-ar", "40", "-f", "f32le", "pipe:1")
      samples = bytes.force_encoding(Encoding::BINARY).unpack("e*")
      return nil if samples.size < 480
      mean = samples.sum / samples.size
      samples.map! { |sample| sample - mean }
      energy = samples.sum { |sample| sample * sample }
      return nil if energy < 1e-12
      score, lag = (12..[40, samples.size / 4].min).map do |candidate|
        total = 0.0
        limit = samples.size - candidate
        index = 0
        while index < limit
          total += samples[index] * samples[index + candidate]
          index += 1
        end
        [total / ([limit, 1].max * energy / samples.size), candidate]
      end.max_by(&:first)
      bpm = 2400.0 / lag
      bpm *= 2 if bpm < 80
      bpm /= 2 if bpm > 175
      { "bpm" => bpm.round(1), "confidence" => score.round(3) }
    rescue Error
      nil
    end

    def separate(audio, directory, options, duration)
      return [[], { "status" => "not_requested", "files" => [] }] unless options[:stems]
      cmd = executable("DEMUCS_BIN", "demucs")
      python = executable("PYTHON_BIN", "python3") || executable("PYTHON_BIN", "python")
      command = cmd ? [cmd] : (python && (begin
        _out, _err, status = Open3.capture3(python, "-c", "import demucs")
        [python, "-m", "demucs.separate"] if status.success?
      end))
      return [[], { "status" => "unavailable", "files" => [] }] unless command
      target = File.join(directory, "stems")
      prepare_dir(target)
      _out, logs = capture!("Demucs separation", *command, "--name", options[:model], "--out", target, audio,
                            timeout: [[duration.to_f.ceil * 8, 1800].max, 57_600].min)
      files = Dir.glob(File.join(target, "**", "*.wav")).sort
      [files, { "status" => files.empty? ? "no_stems_found" : "separated",
                "model" => options[:model], "files" => files.map { |path| path.delete_prefix(directory + File::SEPARATOR) },
                "log_tail" => logs.lines.last(4).join.strip }]
    rescue Error => error
      [[], { "status" => "failed", "files" => [], "message" => error.message }]
    end

    def essentia(audio, directory)
      exe = executable("ESSENTIA_EXTRACTOR", "streaming_extractor_music")
      return { "status" => "unavailable" } unless exe
      name = File.join(directory, "essentia_features.json")
      capture!("Essentia", exe, audio, name, timeout: 900)
      { "status" => "analyzed", "file" => File.basename(name) }
    rescue Error => error
      { "status" => "failed", "message" => error.message }
    end

    def profile_for(mix)
      bands = mix.fetch("spectral_bands_db", {})
      low = ((bands.fetch("sub_25_120_hz", -36.0) - bands.fetch("low_mid_120_500_hz", -36.0) + 8.0) / 24.0).clamp(0.0, 1.0)
      bright = ((bands.fetch("high_4000_plus_hz", -36.0) - bands.fetch("mid_500_4000_hz", -36.0) + 10.0) / 24.0).clamp(0.0, 1.0)
      bpm = mix.dig("tempo", "bpm")
      { "genre" => "industrial_techno", "measured_bpm" => bpm,
        "tempo_confidence" => mix.dig("tempo", "confidence"), "target_bpm" => bpm ? bpm.to_f.clamp(118, 160).round : 138,
        "meter" => "4/4", "parameters" => {
          "rumble_level" => (0.09 + 0.10 * low).round(3), "rumble_duck_depth" => (0.70 + 0.20 * low).round(3),
          "hat_probability" => (0.46 + 0.30 * bright).round(3), "metal_probability" => (0.07 + 0.13 * bright).round(3),
          "distortion_drive" => (1.6 + 0.9 * bright).round(2)
        }, "production" => "straight four-on-the-floor; distorted rumble; metallic hits; evolving industrial textures; no hip-hop swing" }
    end

    def write_report(path, tracks, separation, profile)
      lines = ["# Audio reference analysis", "", "Estimated tempo: #{tracks.dig('mix', 'tempo', 'bpm') || 'unknown'} BPM",
               "Stem separation: #{separation['status']}", "", "## Parts"]
      tracks.each { |name, row| lines << "- #{name}: #{row['duration_seconds'] || '?'} s; RMS #{row['rms_db'] || 'unknown'} dB" }
      lines.concat(["", "## Frequency bands"])
      tracks.fetch("mix").fetch("spectral_bands_db", {}).each { |name, value| lines << "- #{name}: #{value || 'not measured'} dB" }
      lines.concat(["", "## Production profile", JSON.pretty_generate(profile),
                    "", "Audio only was analyzed. The renderer creates new material and does not use source audio or stems.", ""])
      File.write(path, lines.join("\n"))
    end

    def probe_duration(path, ffprobe)
      out, = capture!("ffprobe duration", ffprobe, "-v", "error", "-show_entries", "format=duration",
                      "-of", "default=noprint_wrappers=1:nokey=1", path)
      Float(out.strip)
    rescue Error, ArgumentError
      nil
    end

    def capture!(label, *command, timeout: 120)
      stdout, stderr, status = Timeout.timeout(timeout) { Open3.capture3(*command) }
      return [stdout, stderr] if status.success?
      raise Error, "#{label} exited #{status.exitstatus}: #{stderr.lines.last(5).join.strip}"
    rescue Errno::ENOENT => error
      raise Error, "#{label}: executable missing (#{error.message})"
    rescue Timeout::Error
      raise Error, "#{label} timed out after #{timeout}s"
    end

    def executable(env, name)
      name = ENV[env].to_s.strip.then { |value| value.empty? ? name : value }
      if name.include?(File::SEPARATOR)
        File.file?(name) && File.executable?(name) ? name : nil
      else
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
           .find { |path| File.file?(path) && File.executable?(path) }
      end
    end

    def number(text, pattern)
      match = text.match(pattern)
      match && Float(match[1])
    rescue ArgumentError
      nil
    end
  end

  # A separate, original industrial-techno engine. The existing Dilla showcase is untouched.
  module IndustrialTechno
    TAU = Math::PI * 2
    ROOTS = [43.65, 46.25, 49.0, 51.91, 55.0].freeze
    MAX_BARS = 32
    module_function

    def run(argv)
      opts = { bpm: nil, bars: 16, seed: 42 }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby dilla.rb industrial-techno [options]"
        parser.on("--bpm N", Float) { |v| opts[:bpm] = v }
        parser.on("--bars N", Integer) { |v| opts[:bars] = v }
        parser.on("--seed N", Integer) { |v| opts[:seed] = v }
        parser.on("--out PATH") { |v| opts[:out] = v }
        parser.on("--reference DIR_OR_JSON") { |v| opts[:reference] = v }
        parser.on("-h", "--help") { puts parser; return 0 }
      end.parse!(argv)
      raise ArgumentError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      raise ArgumentError, "bars must be 1..#{MAX_BARS}" unless opts[:bars].between?(1, MAX_BARS)
      profile = read_profile(opts[:reference])
      bpm = (opts[:bpm] || profile&.fetch("target_bpm", nil) || 138).to_f
      raise ArgumentError, "BPM must be 90..190" unless bpm.finite? && bpm.between?(90, 190)
      path = File.expand_path(opts[:out] || File.join(ENV.fetch("XDG_DATA_HOME", File.expand_path("~/Documents")), "dilla-renders", "industrial-techno-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav"))
      raise ArgumentError, "refusing to overwrite existing output: #{path}" if File.exist?(path)
      render(path, bpm:, bars: opts[:bars], seed: opts[:seed], profile:)
      puts "dilla0: wrote original industrial techno #{path} (#{bpm.round(1)} BPM, #{opts[:bars]} bars)"
      puts "dilla0: reference profile applied" if profile
      0
    rescue ArgumentError, JSON::ParserError => error
      warn "dilla0: #{error.message}"
      2
    rescue StandardError => error
      warn "dilla0: render failed (#{error.class}: #{error.message})"
      1
    end

    def render(path, bpm: 138, bars: 16, seed: 42, profile: nil)
      raise ArgumentError, "bars must be 1..#{MAX_BARS}" unless bars.to_i.between?(1, MAX_BARS)
      beat = 60.0 / bpm.to_f
      step = beat / 4.0
      frames = (bars * 4 * beat * SAMPLE_RATE).round
      rng = Random.new(seed)
      root = ROOTS.sample(random: rng)
      pattern = events(bars, rng, root:, step:, profile:)
      p = profile&.fetch("parameters", {}) || {}
      rumble_level = Float(p.fetch("rumble_level", 0.14)).clamp(0.05, 0.35)
      duck_depth = Float(p.fetch("rumble_duck_depth", 0.82)).clamp(0.3, 0.95)
      drive = Float(p.fetch("distortion_drive", 2.0)).clamp(1.0, 4.0)
      break_start = bars >= 8 ? (bars * 0.72).floor : bars + 1
      break_end = bars >= 8 ? [(bars * 0.84).floor, break_start + 1].max : break_start
      brown = 0.0
      prev_noise = 0.0
      FileUtils.mkdir_p(File.dirname(path))
      WAV.write_stream(path, frames:, channels: 2, bits: 24, block_size: 8192) do |offset, count|
        left = Array.new(count, 0.0)
        right = Array.new(count, 0.0)
        count.times do |local|
          i = offset + local
          time = i.to_f / SAMPLE_RATE
          beat_i = (time / beat).floor
          beat_age = time - beat_i * beat
          bar = beat_i / 4
          step_i = (time / step).floor
          step_age = time - step_i * step
          noise = rng.rand * 2.0 - 1.0
          gap = bars >= 8 && bar >= break_start && bar < break_end
          kick_env = gap ? 0.0 : Math.exp(-beat_age * 10.5)
          phase = TAU * (45 * beat_age + 105.0 / 24 * (1.0 - Math.exp(-24 * beat_age)))
          kick = gap ? 0.0 : Math.sin(phase) * kick_env * 0.82 + Math.sin(TAU * 2100 * beat_age) * Math.exp(-beat_age * 190) * 0.12
          brown = brown * 0.997 + noise * 0.025
          duck = 1.0 - kick_env * duck_depth
          rumble = (Math.sin(TAU * root * time) * rumble_level +
                    Math.sin(TAU * root * 1.4142 * time) * rumble_level * 0.39 + brown * rumble_level) * duck
          level = gap ? 0.18 : (bar < 4 ? 0.35 : (bar < 8 ? 0.58 : (bar < 12 ? 0.92 : 1.0)))
          drone = level * (Math.sin(TAU * root * 1.4983 * time) * 0.07 +
                           Math.sin(TAU * root * 2.003 * time) * 0.045 +
                           Math.sin(TAU * root * 2.997 * time) * 0.026) * duck
          bass = 0.0
          if (event = pattern[:bass][step_i]) && step_age < event[:length]
            bphase = TAU * event[:frequency] * step_age
            saw = 2.0 * ((bphase / TAU) % 1.0) - 1.0
            bass = (Math.sin(bphase) * 0.6 + saw * 0.4) * Math.exp(-step_age * event[:decay]) * event[:gain] * level * duck
          end
          clang = 0.0
          pan_m = 0.0
          if (event = pattern[:metal][step_i]) && step_age < event[:decay] * 5
            env = Math.exp(-step_age / event[:decay])
            mphase = TAU * (event[:frequency] * step_age + event[:sweep] * (1.0 - Math.exp(-step_age * 18)) / 18)
            clang = event[:gain] * env * (Math.sin(mphase) + 0.45 * Math.sin(mphase * 1.414) + 0.22 * Math.sin(mphase * 2.31))
            pan_m = event[:pan]
          end
          hat = 0.0
          pan_h = 0.0
          if (event = pattern[:hats][step_i]) && step_age < 0.09
            hat = (noise - prev_noise) * event[:gain] * Math.exp(-step_age * event[:decay])
            pan_h = event[:pan]
          end
          prev_noise = noise
          mono = Math.tanh((kick + rumble + drone + bass + clang + hat + noise * level * 0.012) * drive) / Math.tanh(drive)
          side = clang * pan_m * 0.42 + hat * pan_h * 0.65
          left[local] = ((mono - side) * 0.78).clamp(-0.98, 0.98)
          right[local] = ((mono + side) * 0.78).clamp(-0.98, 0.98)
        end
        [left, right]
      end
      path
    end

    def events(bars, rng, root:, step:, profile:)
      p = profile&.fetch("parameters", {}) || {}
      metal_chance = Float(p.fetch("metal_probability", 0.15)).clamp(0.02, 0.45)
      hat_chance = Float(p.fetch("hat_probability", 0.68)).clamp(0.1, 0.98)
      metal, hats, bass = {}, {}, {}
      motif = [0, 3, 5, 8, 10, 7, 5, 2, 0, 3, 6, 10, 8, 5, 3, 2]
      (bars * 16).times do |index|
        bar = index / 16
        pos = index % 16
        next if bar.zero?
        if pos.even? || rng.rand < hat_chance
          hats[index] = { gain: pos % 8 == 0 ? 0.15 : 0.085, pan: rng.rand * 1.5 - 0.75, decay: 42 + rng.rand * 34 }
        end
        if [0, 6, 10].include?(pos) || (pos == 14 && rng.rand < 0.55)
          midi = motif[(bar * 3 + pos) % motif.size]
          bass[index] = { frequency: root * 2.0**(midi / 12.0), gain: 0.10 + rng.rand * 0.09,
                          decay: 5.0 + rng.rand * 5.0, length: step }
        end
        next if bar < 2
        next unless rng.rand < metal_chance || pos == 14
        metal[index] = { frequency: [277.0, 311.0, 419.0, 503.0, 613.0, 827.0, 1103.0, 1451.0].sample(random: rng),
                         sweep: 90.0 + rng.rand * 820.0, gain: 0.12 + rng.rand * 0.13,
                         pan: rng.rand * 1.7 - 0.85, decay: 0.16 + rng.rand * 0.42 }
      end
      { metal:, hats:, bass: }
    end

    def read_profile(path)
      candidate = if path
                    expanded = File.expand_path(path)
                    File.directory?(expanded) ? File.join(expanded, "profile.json") : expanded
                  else
                    File.join(Reference::REFERENCE_ROOT, "latest_profile.json")
                  end
      return nil unless File.file?(candidate)
      profile = JSON.parse(File.read(candidate))
      raise ArgumentError, "profile genre must be industrial_techno" unless profile["genre"] == "industrial_techno"
      profile
    end
  end
end
