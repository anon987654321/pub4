# frozen_string_literal: true

# ----------------------------------------------------------------- streamer
# One pass rendered a block at a time instead of whole. The plan is the same one a whole render
# makes, with the notes kept and not yet sounded; the streamer sounds each note when its block comes
# up, reading it a block at a time so that its oscillators and filters carry on where they stopped,
# and sends the sum through the effects as stateful processors, in this order: colour, echo, the
# chords' level, the kick's duck, the texture, then the drums over them. A pass cut into blocks of
# any size gives the same samples, within float rounding, as one block.
#
# Stereo by default: each note is panned by its voice's group and by where it lies on the
# keyboard, each drum by its role, the colour and the room run once for each channel with
# decorrelated delays on the right, and the echo is ping-pong. `mono: true` runs one channel and
# gives a flat array.
#
# The source fades out over its last beats and in over its first, equal power, so one pass can
# begin under the end of another; the echo and the room keep ringing after the source stops, up to
# the echo's tail.
class Streamer
  attr_reader :plan, :position, :total, :source_end, :fade_out, :beat, :channels, :hits
  # Live moves: the drums' level (0 for a dropout) and the echo's send boost.
  attr_accessor :drums_gain

  # `fade_in` is a number of samples, `fade_out_beats` a number of this pass's beats.
  # `ring` lets the last notes ring out after the pass's end, for a render that stands alone.
  def initialize(data, options, fade_in: 0, fade_out_beats: 0, play_tail: true, ring: false)
    @data = data
    @options = options
    @channels = options[:mono] ? 1 : 2
    @plan = plan_pass(data, options, capture: true)
    @seq = @plan.seq
    @bpm = @plan.bpm
    @position = 0
    @drums_gain = 1.0
    @ahead = Stereo.zeros(@channels, 0)
    @beat = (60.0 / @bpm * SAMPLE_RATE).round
    @source_end = (@plan.names.size * @plan.beats * @beat).round # whole beats of whole samples, so a join falls on a bar line
    @fade_in = fade_in
    @fade_out = (fade_out_beats * @beat).round
    @ring = ring
    build_source
    build_chain
    build_drums
    build_noise
    @total = @source_end + (play_tail ? @tail : 0)
    @total = [@total, @source_end + (1.5 * SAMPLE_RATE).round].max if ring # the longest release of a voice
  end

  def silent_after_source? = @position >= @source_end

  # Seconds the pass plays before its tail.
  def seconds = @source_end / SAMPLE_RATE.to_f

  # The next `count` samples, fewer at the end of the pass: an array for one channel, [left, right]
  # for two.
  def next_block(count)
    frame = take(count)
    @channels == 1 ? frame.first : frame
  end

  # Render the first `count` samples now and hand them out when asked: a deck prepared while
  # the other one plays.
  def prefetch(count)
    Stereo.concat!(@ahead, render_block([count, @total - @position].min)) unless @position >= @total
  end

  def echo_boost=(factor)
    @echo&.boost = factor
  end

  def echo_boost = @echo ? @echo.boost : 1.0

  # Whether anything of the pass is rendered and not yet handed out.
  def finished? = @position >= @total && @ahead.first.empty?

  private

  def take(count)
    have = @ahead.first.size
    return Stereo.shift!(@ahead, count) if have >= count

    frame = Stereo.shift!(@ahead, have)
    count -= have
    return frame if count <= 0 || @position >= @total

    Stereo.concat!(frame, render_block(count))
  end

  def render_block(count)
    count = [count, @total - @position].min
    return Stereo.zeros(@channels, 0) if count <= 0

    from = @position
    dry = fade(@bank.block(from, count, @channels), from)
    wet = add_noise(chain(dry, from), from)
    @position += count
    wet
  end

  # One processor for each channel; the block receives the channel number.
  def pair
    Stream::Pair.new(*Array.new(@channels) { |c| yield c })
  end

  # ------------------------------------------------------------- the source
  def build_source
    entries = []
    stems = []
    pans = @data.fetch('stereo')
    @plan.parts.each do |part|
      group = part.voice['group'] || 'sine'
      centre = pans.fetch('groups').fetch(group, 0.0)
      if part.voice['family'] == 'fluid'
        level = 10.0**(part.voice.fetch('gain', 0.0) / 20.0)
        stems << [Fluid.render(part.plucks, part.voice), level * part.gain, centre]
        next
      end
      swell = part.swell && swell_proc(*part.swell)
      step = 15.0 / @bpm
      part.plucks.each do |p|
        notes = Array(p.midi)
        notes.each do |midi|
          start = [((p.base + p.off.clamp(-MAX_OFFSET, MAX_OFFSET)) * SAMPLE_RATE).to_i, 0].max
          make = lambda do
            Voices.cached_reader(part.voice, midi, p.dur, 0.22 * p.gain / Math.sqrt(notes.size), velocity: p.gain, detune: @seq.detune,
                                                                                           step:, registration: part.voice['registration'])
          end
          entries << Stream::Bank::Entry.new(start, make, part.gain, swell, note_pan(centre, midi, pans))
        end
      end
    end
    stems.each { |samples, level, centre| entries << Stream::Bank::Entry.new(0, -> { Voices::Reader.of(samples) }, level, nil, centre) }
    @bank = Stream::Bank.new(entries)
  end

  # A voice group's place, and a spread of the notes across it by pitch: the low notes stay near
  # the middle, the high ones go out. Static, so a note keeps its place for its whole life.
  def note_pan(centre, midi, pans)
    reach = ((midi - 60) / 24.0).clamp(-1.0, 1.0)
    reach *= pans.fetch('low_reach') if midi < pans.fetch('low_below')
    (centre + (pans.fetch('spread') * reach)).clamp(-1.0, 1.0)
  end

  # The pad that swells with the energy: linear between the beats' levels, from a quarter to full.
  def swell_proc(energies, beat_samples)
    return ->(_at) { 1.0 } if energies.nil? || energies.empty?

    lambda do |at|
      pos = at.to_f / beat_samples
      a = energies[[pos.floor, energies.size - 1].min]
      b = energies[[pos.floor + 1, energies.size - 1].min]
      0.25 + (0.75 * (a + ((b - a) * (pos - pos.floor))))
    end
  end

  # Equal-power fades at the ends of the source, and silence after its end.
  def fade(frame, from)
    return frame if @fade_in.zero? && @fade_out.zero? && (@ring || from + frame.first.size <= @source_end)

    frame.map do |channel|
      channel.each_with_index.map do |v, i|
        at = from + i
        gain = 1.0
        gain = Math.sin(Math::PI / 2 * at / @fade_in) if at < @fade_in
        if at >= @source_end then gain = @ring ? gain : 0.0
        elsif @fade_out.positive? && at >= @source_end - @fade_out then gain *= Math.cos(Math::PI / 2 * (at - (@source_end - @fade_out)) / @fade_out)
        end
        v * gain
      end
    end
  end

  # ------------------------------------------------------------- the effects
  def build_chain
    options = @options
    seq = @seq
    seed = @plan.seed
    @vcs = seq.vcs_amount(options[:vcs])
    sonitex = seq.sonitex_settings(options[:sonitex], instances: options[:sonitex_instances])
    @sonitex = sonitex && pair { |c| Stream::SonitexStack.new(sonitex.fetch('preset'), sonitex.fetch('instances'), seed + (c * 104_729)) }
    @drum_sonitex_settings = seq.sonitex_settings(options[:drum_sonitex], instances: options[:drum_sonitex_instances]) || sonitex
    @colour_vcs = pair { Stream::Vcs.new(@vcs) }
    echo = seq.echo_settings(flag: options[:echo], mix: options[:echo_mix], feedback: options[:echo_feedback], time_ms: options[:echo_time])
    echo['tail'] = options[:echo_tail] if echo && options[:echo_tail]
    echo['reverb'] = options[:echo_reverb] unless !echo || options[:echo_reverb].nil?
    @echo = echo && echo_line(echo)
    @tail = echo ? (echo.fetch('tail', 4.0) * SAMPLE_RATE).to_i : 0
    texture = @plan.profile_row['texture'] || {}
    @texture = [pair { Stream::Lowpass.new(texture['lowpass']) },
                pair { |c| Stream::Reverb.new(texture['reverb'], side: c.zero? ? :left : :right) },
                pair { |c| Stream::Spring.new(texture['spring'], side: c.zero? ? :left : :right) }]
    @stages = Array(@plan.profile_row['chain']).map do |row|
      Stages.build(row, @data.fetch('stages'), channels: @channels, seed:, end_sample: @source_end, bar_samples: @beat * 4)
    end
  end

  def echo_line(settings)
    delay = settings['time_ms'] ? settings['time_ms'] / 1000.0 : settings.fetch('time_beats') * 60.0 / @bpm
    resets = (1...@plan.names.size).map { |i| (i * @plan.beats * 60.0 / @bpm * SAMPLE_RATE).round }
    args = { delay:, heads: settings.fetch('heads'), intensity: settings.fetch('intensity'), volume: settings.fetch('echo_volume'),
             lowpass: settings['lowpass'], saturation: settings.fetch('saturation', 0.0), reverb: settings.fetch('reverb', 0.0),
             resets:, send: @seq.throws(settings['throws'], @bpm) }
    @channels == 1 ? Stream::EchoLine.new(**args) : Stream::PingPongEcho.new(**args)
  end

  def chain(dry, from)
    out = @sonitex ? @sonitex.process(dry) : dry
    out = @colour_vcs.process(out)
    out = @stages.inject(out) { |frame, stage| stage.process(frame, from) }
    out = echoed(out) if @echo
    out = out.map { |channel| channel.map { |v| v * @chords_gain } } if @chords_gain
    out = out.map { |channel| @duck.apply(channel, from) } if @duck
    out = @texture.inject(out) { |frame, stage| stage.process(frame) }
    @hits.empty? ? out : mix_drums(out, from)
  end

  def echoed(frame) = @channels == 1 ? [@echo.process(frame.first)] : @echo.process(frame)

  # ------------------------------------------------------------- noise and sparkle
  # The layers a profile names under `noise`, over the defaults in the data: air, the bed, dust,
  # and the sparkle with its own echo, ducked by the kick.
  def build_noise
    rows = @plan.profile_row['noise'] || {}
    defaults = @data.fetch('noise')
    seed = @plan.seed
    wanted = lambda do |name|
      row = rows[name]
      row ? defaults.fetch(name).merge(row.is_a?(Hash) ? row : {}) : nil
    end
    seconds = (@source_end + @tail) / SAMPLE_RATE.to_f
    air = wanted.call('air')
    bed = wanted.call('bed')
    @air = air && Array.new(@channels) { |c| Noise::Air.new(air, Zlib.crc32("#{seed}:air:#{c}")) }
    @bed = bed && Array.new(@channels) { |c| Noise::Bed.new(bed, Zlib.crc32("#{seed}:bed:#{c}")) }
    dust = wanted.call('dust')
    @dust_bank = dust && Stream::Bank.new(Noise.dust(dust, Zlib.crc32("#{seed}:dust"), seconds))
    sparkle = wanted.call('sparkle')
    return unless sparkle

    pcs = Chords.midi_notes(@plan.names, search: @plan.search).map { |notes| notes.map { |n| n % 12 }.uniq }
    chord_seconds = @plan.beats * 60.0 / @bpm
    chord_at = ->(t) { pcs[[(t / chord_seconds).floor, pcs.size - 1].min] }
    @sparkle_bank = Stream::Bank.new(Noise.sparkle(sparkle, Zlib.crc32("#{seed}:sparkle"), seconds, chord_at))
    kicks = @hits.select { |r, _| r == 'kick' }.map { |_, t| t }
    @sparkle_duck = kicks.empty? ? nil : Stream::Duck.new(kicks, sparkle.fetch('duck', 0.85), 0.12)
    echo = sparkle['echo']
    return unless echo

    args = { delay: echo.fetch('beats', 0.75) * 60.0 / @bpm, heads: echo.fetch('heads', [1, 2]), intensity: echo.fetch('intensity', 0.55), volume: echo.fetch('volume', 0.7),
             lowpass: echo.fetch('lowpass', 5000), saturation: 0.1 }
    @sparkle_echo = @channels == 1 ? Stream::EchoLine.new(**args) : Stream::PingPongEcho.new(**args)
  end

  def add_noise(frame, from)
    return frame unless @air || @bed || @dust_bank || @sparkle_bank

    count = frame.first.size
    layers = []
    layers << Array.new(@channels) { |c| @air[c].block(count) } if @air
    layers << Array.new(@channels) { |c| @bed[c].block(count) } if @bed
    layers << @dust_bank.block(from, count, @channels) if @dust_bank
    if @sparkle_bank
      glints = @sparkle_bank.block(from, count, @channels)
      glints = glints.map { |channel| @sparkle_duck.apply(channel, from) } if @sparkle_duck
      glints = @channels == 1 ? [@sparkle_echo.process(glints.first)] : @sparkle_echo.process(glints) if @sparkle_echo
      layers << glints
    end
    layers.each { |layer| Stereo.add!(frame, layer) }
    frame
  end

  # ------------------------------------------------------------- the drums
  def build_drums
    seq = @seq
    options = @options
    drums = @plan.drums
    rotation = drums == 'rotate' ? @data.fetch('drum_patterns').keys : drums
    @hits = drums ? seq.drum_hits(rotation, @bpm, @source_end / SAMPLE_RATE.to_f) : []
    @levels = seq.mix(options[:mix])
    @chords_gain = @hits.empty? ? nil : 10.0**(@levels.fetch('chords') / 20.0)
    # a profile's own pump, else the master's light duck: the instruments give way to the kick
    sidechain = @plan.profile_row['sidechain'] || (options[:master] == false ? nil : @data.dig('master', 'duck'))
    amount = sidechain ? sidechain.fetch('amount', 0.0) * seq.pd_amount : 0.0
    @duck = sidechain && !amount.zero? ? Stream::Duck.new(@hits.select { |r, _| r == 'kick' }.map { |_, t| t }, amount, sidechain.fetch('release', 0.15)) : nil
    return if @hits.empty?

    kit = seq.kit_sounds
    @drum_bank = Stream::Bank.new(drum_entries(kit))
    crush = @plan.profile_row['drum_crush']
    @drum_crush = crush && pair { Stream::Crush.new(crush.fetch('bits'), 1.0 / crush.fetch('rate')) }
    @rumble_amount = kit && @plan.profile_row.dig('rumble', 'amount')
    @rumble = rumble_chain(kit) if @rumble_amount
    drum_sonitex = @drum_sonitex_settings
    @drum_sonitex = drum_sonitex && pair { |c| Stream::SonitexStack.new(drum_sonitex.fetch('preset'), drum_sonitex.fetch('instances'), @plan.seed + 1 + (c * 104_729)) }
    drum_vcs = options[:drum_vcs].nil? ? @vcs : options[:drum_vcs].to_f.clamp(0.0, 1.0)
    @drum_vcs = pair { Stream::Vcs.new(drum_vcs) }
    @master_vcs = pair { Stream::Vcs.new(@vcs * 0.5) }
    @separate_bus = @drum_sonitex || @vcs.positive? || @drum_crush || @rumble
  end

  def drum_entries(kit)
    closers = @hits.select { |r, *| r == 'hat' }.map { |_, t, *| t }
    drum_pans = @data.fetch('stereo').fetch('drums')
    @hits.each_with_index.filter_map do |(role, time, strength), hit_index|
      make = lambda do
        sample = kit ? kit[role] : Drums.new(@plan.seed + ((hit_index + 1) * 104_729)).sounds.fetch(role)
        if sample && kit && role == 'open' && (nxt = closers.find { |t| t > time })
          sample = sample.first(((nxt - time) * SAMPLE_RATE).to_i)
          fade = [130, sample.size].min
          fade.times { |k| sample[sample.size - 1 - k] *= k / fade.to_f }
        end
        Voices::Reader.of(sample || [])
      end
      next if kit && kit[role].nil?

      accent = strength.nil? ? 1.0 : strength.to_f.clamp(0.0, 1.0)
      variation = case role
                  when 'hat' then [0.68, 0.92, 0.76, 0.84][hit_index % 4]
                  when 'snare' then hit_index.odd? ? 0.92 : 1.0
                  else hit_index.odd? ? 0.94 : 1.0
                  end
      gain = 0.8 * (10.0**(@levels.fetch(role, 0.0) / 20.0)) * accent * variation
      lean = %w[hat open perc shaker].include?(role) && hit_index.odd? ? -0.12 : 0.0 # the hats alternate a little
      Stream::Bank::Entry.new((time * SAMPLE_RATE).to_i, make, gain, nil, drum_pans.fetch(role, 0.0) + lean)
    end
  end

  # The drums enter at equal power over the crossfade, and a dropout holds them at nothing, with
  # ten milliseconds to get there and back so it does not click.
  def drum_level(frame, from)
    ramp = (0.01 * SAMPLE_RATE).round
    target = @drums_gain
    previous = @drums_applied || target
    @drums_applied = target
    return frame if @fade_in.zero? && target == 1.0 && previous == 1.0 && from >= @fade_in

    frame.map do |channel|
      channel.each_with_index.map do |v, i|
        at = from + i
        gain = at < @fade_in ? Math.sin(Math::PI / 2 * at / @fade_in) : 1.0
        level = i < ramp ? previous + ((target - previous) * i / ramp) : target
        v * gain * level
      end
    end
  end

  # The low end grown from the kicks: a room, a lowpass, drive, two more lowpasses, scaled by a
  # fixed gain found once from a single kick, where a whole render scales by its own peak. It is
  # mono, the same in both channels.
  def rumble_chain(kit)
    build = -> { [Stream::Reverb.new(0.8), Stream::SmoothLowpass.new(180.0), Stream::SmoothLowpass.new(110.0), Stream::SmoothLowpass.new(110.0)] }
    run = lambda do |stages, block|
      room, first, second, third = stages
      third.process(second.process(Percussion.dirt(first.process(room.process(block)), 0.55)))
    end
    one = kit['kick'] + Array.new(SAMPLE_RATE * 2, 0.0)
    peak = run.call(build.call, one).map(&:abs).max.to_f
    @rumble_scale = peak.zero? ? 1.0 : 0.6 / peak
    @rumble_run = run
    @rumble_stages = build.call
    kicks = @hits.each_with_object([]) { |(role, t, v), list| list << [(t * SAMPLE_RATE).to_i, kit['kick'], v || 1.0] if role == 'kick' }
    @kick_bank = Stream::Bank.new(kicks.map { |start, sample, v| Stream::Bank::Entry.new(start, -> { Voices::Reader.of(sample) }, v, nil, nil) })
  end

  def mix_drums(chords, from)
    count = chords.first.size
    drums = drum_level(@drum_bank.block(from, count, @channels), from)
    if @separate_bus
      if @rumble
        grown = @rumble_run.call(@rumble_stages, @kick_bank.block(from, count, 1).first)
        drums = drums.map { |channel| channel.each_with_index.map { |v, i| v + (grown[i] * @rumble_scale * @rumble_amount) } }
      end
      drums = @drum_crush.process(drums) if @drum_crush
      drums = @drum_sonitex.process(drums) if @drum_sonitex
      drums = @drum_vcs.process(drums)
      out = chords.each_with_index.map { |channel, c| channel.each_with_index.map { |v, i| v + drums[c][i] } }
      out = @master_vcs.process(out)
    else
      out = chords.each_with_index.map { |channel, c| channel.each_with_index.map { |v, i| v + drums[c][i] } }
    end
    out.map { |channel| channel.map { |v| Colour.soft_limit(v) } }
  end
end
