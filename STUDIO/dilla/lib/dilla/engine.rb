# Reference analysis and industrial-techno generation stay in their own modules.
require_relative "reference"
require_relative "industrial_techno"

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
    o.on('--render', 'Write one random take to a new file under the renders folder instead of playing live') { options[:render] = true }
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
    o.on('--replace', 'Explicitly replace an existing WAV or MIDI take') { options[:replace] = true }
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
    o.on('--drum-balance DB', Float, 'Reference-derived dB shift to all drum roles, bounded to +/-2 dB') { |v| options[:drum_balance] = v.clamp(-2.0, 2.0) }
    o.on('--chord-balance DB', Float, 'Reference-derived dB shift to chords, bounded to +/-2 dB') { |v| options[:chord_balance] = v.clamp(-2.0, 2.0) }
    o.on('--pool POOL', %w[essential all], 'With --play: essential progressions (default) or all') { |v| options[:pool] = v }
    o.on('--quick', 'Render the first progression as a smoke test') { options[:quick] = true }
  end.parse!(argv)
  options[:live] = true if live_argument

  data = JSON.parse(File.read(File.expand_path('../../data/dilla.json', __dir__)))
  if bare_run?(options)
    if options[:out] || options[:midi] || options[:render]
      randomize_take!(data, options)
    else
      # A bare run plays live, in real time, from every progression and style, and never stops.
      options[:play] = true
      options[:pool] ||= 'all'
    end
  end

  unless options[:replace] || options[:play] || options[:live] || options[:list] || options[:arp] == 'list'
    outputs = []
    if options[:out]
      outputs << options[:out]
    elsif options[:quick]
      outputs << 'out/quick.wav'
    elsif options[:showcase] || (options[:prog].nil? && !options[:random] && !options[:quick] && options[:mode] != 'organ')
      outputs << File.expand_path('../../dilla.wav', __dir__)
    end
    outputs << options[:midi] if options[:midi]
    existing = outputs.find { |path| File.exist?(path) || File.symlink?(path) }
    abort "studio0: refusing to overwrite existing take #{existing.inspect}; choose a new path or pass --replace" if existing
  end

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

# Flags that choose what is played. A run that names none of them is a bare run, and a bare
# run is a new take every time; --showcase is the way to the fixed Blue Hour piece.
CONTENT_FLAGS = %i[showcase live list prog random drums kit profile arp arp_style repeat voice mode play quick
                   patch_per_chord].freeze

def bare_run?(options) = (options.keys & CONTENT_FLAGS).empty?

# A random take from the whole of the data: any progression, mode, arp or repeat style, patch,
# groove profile, kit and drum pattern, each from its own shuffle bag so a bare run never plays
# the same thing twice running within a cycle. It writes under the renders folder, outside the
# repo, and never over an earlier take.
def randomize_take!(data, options)
  seed = options[:seed] || Random.new_seed % 1_000_000
  playlist = Playlist.new(data, Random.new(seed), pool: 'all')
  profile = data.fetch('groove_profiles').keys.sort.sample(random: Random.new(seed))
  pick = playlist.draw(profile:, mode: nil)
  options.merge!(prog: pick[:prog], seed:, profile:, voice: pick[:voice], mode: pick[:mode], random: true,
                 kit: pick[:kit], chord_voices: pick[:voices])
  options[:arp_style] = pick[:style] if pick[:mode] == 'arp'
  options[:repeat] = pick[:style] if pick[:mode] == 'repeat'
  options[:drums] = data.fetch('groove_profiles').fetch(profile)['drums'] || pick[:drums]
  options[:out] ||= File.join(ENV['XDG_DATA_HOME'] || File.expand_path('~/Documents'), 'dilla-renders',
                              Time.now.strftime('%Y-%m-%d'), "dilla-#{Time.now.strftime('%H%M%S')}-#{seed}.wav")
  puts "studio0: new take, seed #{seed}, progression #{pick[:prog]}, #{pick[:mode]}#{pick[:style] ? " #{pick[:style]}" : ''}, " \
       "voice #{pick[:voice]}, profile #{profile}, kit #{pick[:kit]}"
  options
end

# Apply bounded, relative dB moves after loading Dilla's own mix defaults. MASTER
# passes these only when a separated reference supplies usable stem-energy evidence.
def apply_reference_mix_balance(levels, drum_balance: nil, chord_balance: nil)
  adjusted = levels.dup
  unless drum_balance.nil?
    offset = Float(drum_balance).clamp(-2.0, 2.0)
    %w[kick snare clap hat perc].each do |role|
      adjusted[role] = adjusted.fetch(role, 0.0).to_f + offset
    end
  end
  unless chord_balance.nil?
    offset = Float(chord_balance).clamp(-2.0, 2.0)
    adjusted['chords'] = adjusted.fetch('chords', 0.0).to_f + offset
  end
  adjusted
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
  levels = apply_reference_mix_balance(levels, drum_balance: options[:drum_balance], chord_balance: options[:chord_balance])
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
  WAV.write(out, streamer.channels == 1 ? frame.first : frame, bits:, replace: options[:replace])
  if options[:midi]
    FileUtils.mkdir_p(File.dirname(options[:midi]))
    MIDI.write(options[:midi], plan.names, plan.bpm, plan.beats, streamer.hits, search: plan.search, replace: options[:replace])
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
      kit: options[:kit] || section.fetch('kit', 'kit_dust'),
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
  WAV.write(out, combined, replace: options[:replace])
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
