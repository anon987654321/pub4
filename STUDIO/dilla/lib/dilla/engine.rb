# ---------------------------------------------------------------------- CLI
def run(argv)
  live_argument = argv.first == 'live'
  argv = argv.drop(1) if live_argument
  options = {}
  OptionParser.new do |o|
    o.banner = 'Usage: ruby dilla.rb [options]'
    o.on('--showcase', 'Render the four-part Blue Hour composition to dilla.wav') { options[:showcase] = true }
    o.on('--live', 'Loop the showcase through the system audio player') { options[:live] = true }
    o.on('--list', 'List progressions, drum patterns and groove profiles') { options[:list] = true }
    o.on('--progression N', Integer, 'Progression index (see --list)') { |v| options[:prog] = v }
    o.on('--random', 'Random progression and drum pattern (the default groove profile)') { options[:random] = true }
    o.on('--drums NAME', 'Drum pattern name') { |v| options[:drums] = v }
    o.on('--profile NAME', 'Groove profile name') { |v| options[:profile] = v }
    o.on('--groove N', Float, 'pd_amount, 0 to 1.5: how far the profile pulls from the grid') { |v| options[:groove] = v }
    o.on('--bpm N', Float, 'Tempo (default 88)') { |v| options[:bpm] = v }
    o.on('--beats N', Float, 'Beats per chord (default 4)') { |v| options[:beats] = v }
    o.on('--seed N', Integer, 'Seed: the same seed plays the same render') { |v| options[:seed] = v }
    o.on('--out PATH', 'Output WAV path') { |v| options[:out] = v }
    o.on('--midi PATH', 'Also write a Standard MIDI File') { |v| options[:midi] = v }
    o.on('--no-voice-search', 'Voice each chord by nearest tones only, without the octave search') { options[:plain] = true }
    o.on('--arp [PATTERN]', 'Play each chord one note at a time: up, down, updown, converge, random_seeded') { |v| options[:arp] = v || true }
    o.on('--strum [MS]', Float, 'Stagger the notes of each chord, lowest first, by MS milliseconds (default from the data)') { |v| options[:strum] = v || true }
    o.on('--pad', 'A soft sustained pad under the arpeggio') { options[:pad] = true }
    o.on('--echo [HEADS]', 'Tape space echo; heads such as 1 or 1,2 or 1,2,3') { |v| options[:echo] = v || true }
    o.on('--echo-mix N', Float, 'Echo volume against the dry sound') { |v| options[:echo_mix] = v }
    o.on('--echo-feedback N', Float, 'Echo intensity, 0 to 0.9: how much of each repeat comes round again') { |v| options[:echo_feedback] = v }
    o.on('--echo-time MS', Float, 'Echo base delay in milliseconds (default a dotted eighth)') { |v| options[:echo_time] = v }
    o.on('--play', '--endless', 'Never stop: render the next progression while this one plays') { options[:play] = true }
    o.on('--player CMD', 'The command that plays a wav (default afplay, else ffplay)') { |v| options[:player] = v }
    o.on('--passes N', Integer, 'With --play, stop after N progressions') { |v| options[:passes] = v }
    o.on('--voice NAME', 'The voice that plays the notes (see data/dilla.json): sine, moog_*, rhodes_*, dfam') { |v| options[:voice] = v }
    o.on('--repeat [STYLE]', '--comp [STYLE]', 'Strike the whole chord again on the steps of a style instead of arpeggiating') { |v| options[:repeat] = v || true }
    o.on('--mode MODE', 'arp, repeat or pad: force how the chords are played') { |v| options[:mode] = v }
    o.on('--arp-rate N', 'Sixteenths per arp note: 2 eighth, 3 dotted eighth, 4 quarter, 6, 8; 3T for triplets') { |v| options[:arp_rate] = v }
    o.on('--arp-style NAME', 'A row of arp.styles in data/dilla.json') { |v| options[:arp_style] = v }
    o.on('--sonitex [PRESET]', 'The 12-bit sampler colour chain on the voice bus') { |v| options[:sonitex] = v || true }
    o.on('--sonitex-instances N', Integer, 'Run it 1 to 3 times: one is a colour, three are a sound') { |v| options[:sonitex_instances] = v }
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

  if options[:play]
    play_forever(data, options)
  elsif options[:live]
    play_showcase(data, options)
  elsif options[:list]
    puts 'Progressions:'
    progressions.each_with_index { |chords, i| puts format('%4d  %s', i, chords.join(' ')) }
    puts
    puts "Drum patterns: #{data['drum_patterns'].keys.join(', ')}"
    puts "Groove profiles: #{data['groove_profiles'].keys.join(', ')}"
  elsif options[:showcase] || (options[:prog].nil? && !options[:random] && !options[:quick])
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

# One render: the options name a progression or let the seed choose one. Returns the output path.
def render(data, options)
  progressions = data.fetch('progressions')
  seed = options[:seed] || Random.new_seed % 1_000_000
  pick = Random.new(seed)
  index = options[:section_index] || (options[:quick] ? 0 : (options[:prog] || pick.rand(progressions.size)))
  names = options[:names] || progressions.fetch(index) { abort "No progression: #{index}" }
  drums = options[:drums] || (options[:random] ? data['drum_patterns'].keys.sample(random: pick) : nil)
  profile = options[:profile] || data.fetch('default_profile')

  seq = Sequencer.new(data, profile_name: profile, pd_amount: options[:groove], seed: seed,
                            transpose: options[:transpose] || 0, wrap: options[:wrap])
  bpm = options[:bpm] || seq.bpm
  beats = options[:beats] || 4.0
  voice = seq.voice_spec(options[:voice])
  search = !options[:plain]
  mode = play_mode(options, seq)
  warn_past_nyquist(names, search, options)
  buf =
    case mode
    when 'arp'
      arp = seq.arp_settings(options[:arp], style: options[:arp_style], rate: parse_rate(options[:arp_rate]))
      seq.render_arp(names, bpm, beats, arp, search:, pad: options[:pad], voice:)
    when 'repeat'
      seq.render_repeat(names, bpm, beats, seq.comp_settings(options[:repeat] || true), search:, voice:)
    else
      seq.render_chords(names, bpm, beats, search:, strum: seq.strum(options[:strum]))
    end
  if options[:melody]
    beat_seconds = 60.0 / bpm
    plucks = options[:melody].map do |beat, midi, length, gain|
      Pluck.new(beat.to_f * beat_seconds, 0.0, midi.to_i, length.to_f * beat_seconds, gain.to_f)
    end
    seq.sound(buf, plucks, seq.voice_spec(options[:melody_voice] || 'rhodes_mark1'))
  end
  vcs = seq.vcs_amount(options[:vcs])
  buf = seq.colour(buf, seq.sonitex_settings(options[:sonitex], instances: options[:sonitex_instances]), vcs)
  echo = seq.echo_settings(flag: options[:echo], mix: options[:echo_mix], feedback: options[:echo_feedback], time_ms: options[:echo_time])
  echo['tail'] = options[:echo_tail] if echo && options[:echo_tail]
  buf = seq.echo(buf, echo, bpm, resets: (1...names.size).map { |i| (i * beats * 60.0 / bpm * SAMPLE_RATE).round }) if echo
  seconds = buf.size / SAMPLE_RATE.to_f
  hits = drums ? seq.drum_hits(drums, bpm, seconds) : []
  levels = seq.mix(options[:mix])
  buf = seq.scale(buf, levels.fetch('chords')) unless hits.empty?
  buf = seq.duck(buf, hits)
  buf = FX.apply(buf, data['groove_profiles'].fetch(profile))
  buf = seq.overlay_drums(buf, hits, levels, vcs) if drums
  return buf if options[:buffer_only]

  out = options[:out] || (options[:quick] ? 'out/quick.wav' : "out/progression_#{index}#{drums ? "_#{drums}" : ''}.wav")
  FileUtils.mkdir_p(File.dirname(out))
  WAV.write(out, buf)
  if options[:midi]
    FileUtils.mkdir_p(File.dirname(options[:midi]))
    MIDI.write(options[:midi], names, bpm, beats, hits, search:)
  end
  puts "Wrote #{out} (#{seconds.round(2)}s) progression #{index}: #{names.join(' ')}"
  puts "  drums=#{drums || 'none'} profile=#{profile} mode=#{mode} voice=#{voice['name']} groove=#{seq.pd_amount} bpm=#{bpm} seed=#{seed}"
  out
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
    section_options = {
      names: section.fetch('progression'),
      section_index: index,
      bpm: section.fetch('bpm'),
      beats: section.fetch('beats_per_chord', 2.0),
      voice: section.fetch('voice'),
      mode: section.fetch('mode', 'repeat'),
      repeat: section.fetch('repeat', 'half_note_pulse'),
      profile: section.fetch('profile', 'soft_swing'),
      drums: section.fetch('drums'),
      echo: section.fetch('echo', false),
      echo_mix: section['echo_mix'],
      echo_feedback: section['echo_feedback'],
      echo_time: section['echo_time_ms'],
      echo_tail: section['echo_tail_seconds'],
      mix: section.fetch('mix', {}),
      melody: section['melody'],
      melody_voice: section['melody_voice'],
      seed: seed + (index * 97),
      groove: options[:groove],
      transpose: options[:transpose],
      wrap: options[:wrap],
      plain: options[:plain],
      sonitex: options[:sonitex],
      sonitex_instances: options[:sonitex_instances],
      vcs: options[:vcs],
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

# A shuffle bag: every item comes out once before any comes out again, and the first of a new
# bag is never the last of the old one. The state is a plain hash, so a restart can go on.
def play_forever(data, options)
  rng = Random.new(options[:seed] || Random.new_seed)
  dir = options[:out] ? File.dirname(options[:out]) : 'out/play'
  FileUtils.mkdir_p(dir)
  state_path = File.join(dir, 'play_state.json')
  state = (JSON.parse(File.read(state_path)) rescue {})
  playlist = Playlist.new(data, rng, state, pool: options[:pool] || 'essential')
  command = player_command(options)
  pid = nil
  trap('INT') { pid && Process.kill('TERM', pid); exit }
  trap('TERM') { pid && Process.kill('TERM', pid); exit }
  (1..(options[:passes] || Float::INFINITY)).each do |pass|
    pick = playlist.draw(mode: options[:mode], voice: options[:voice], profile: options[:profile])
    pass_options = options.merge(prog: pick[:prog], seed: rng.rand(1_000_000), profile: pick[:profile], voice: pick[:voice],
                                 mode: pick[:mode], random: false, quick: false, play: false,
                                 out: File.join(dir, "play_#{pass.odd? ? 'a' : 'b'}.wav"))
    pass_options[:arp_style] = options[:arp_style] || pick[:style] if pick[:mode] == 'arp'
    pass_options[:repeat] = options[:repeat] || pick[:style] if pick[:mode] == 'repeat'
    profile_drums = data['groove_profiles'].fetch(pick[:profile])['drums']
    pass_options[:drums] = options[:drums] || profile_drums
    puts "pass #{pass}: progression #{pick[:prog]} (#{pick[:position]}) mode=#{pick[:mode]} style=#{pick[:style] || '-'} voice=#{pick[:voice]} profile=#{pick[:profile]}"
    path = render(data, pass_options)
    File.write(state_path, JSON.generate(playlist.to_h))
    Process.wait(pid) if pid
    pid = Process.spawn(*command, path)
  end
  Process.wait(pid) if pid
end

run(ARGV) if $PROGRAM_NAME == __FILE__
