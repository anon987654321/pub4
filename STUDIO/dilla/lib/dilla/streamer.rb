# frozen_string_literal: true

# ----------------------------------------------------------------- streamer
# One pass rendered a block at a time instead of whole. The plan is the same one a whole render
# makes, with the notes kept and not yet sounded; the streamer sounds each note when its block comes
# up, reading it a block at a time so that its oscillators and filters carry on where they stopped,
# and sends the sum through the same effects as stateful processors, in the same order: colour,
# echo, the chords' level, the kick's duck, the texture, then the drums over them. A pass cut
# into blocks of any size gives the same samples, within float rounding, as one block.
#
# The source fades out over its last beat and in over its first, equal power, so one pass can
# begin under the end of another; the echo and the room keep ringing after the source stops, up to
# the echo's tail.
class Streamer
  attr_reader :plan, :position, :total, :source_end, :fade_out, :beat
  # Live moves: the drums' level (0 for a dropout) and the echo's send boost.
  attr_accessor :drums_gain

  # `fade_in` is a number of samples, `fade_out_beats` a number of this pass's beats.
  def initialize(data, options, fade_in: 0, fade_out_beats: 0, play_tail: true)
    @data = data
    @options = options
    @plan = plan_pass(data, options, capture: true)
    @seq = @plan.seq
    @bpm = @plan.bpm
    @position = 0
    @drums_gain = 1.0
    @ahead = []
    @beat = (60.0 / @bpm * SAMPLE_RATE).round
    @source_end = (@plan.names.size * @plan.beats * @beat).round # whole beats of whole samples, so a join falls on a bar line
    @fade_in = fade_in
    @fade_out = (fade_out_beats * @beat).round
    build_source
    build_chain
    build_drums
    @total = @source_end + (play_tail ? @tail : 0)
  end

  def silent_after_source? = @position >= @source_end

  # Seconds the pass plays before its tail.
  def seconds = @source_end / SAMPLE_RATE.to_f

  # The next `count` samples, fewer at the end of the pass.
  def next_block(count)
    return @ahead.shift(count) if @ahead.size >= count

    taken = @ahead.shift(@ahead.size)
    count -= taken.size
    return taken if count <= 0 || finished?

    taken + render_block(count)
  end

  # Render the first `count` samples now and hand them out when asked: a deck prepared while
  # the other one plays.
  def prefetch(count)
    @ahead.concat(render_block([count, @total - @position].min)) unless finished?
  end

  def echo_boost=(factor)
    @echo&.boost = factor
  end

  def echo_boost = @echo ? @echo.boost : 1.0

  # Whether anything of the pass is rendered and not yet handed out.
  def finished? = @position >= @total && @ahead.empty?

  private

  def render_block(count)
    count = [count, @total - @position].min
    return [] if count <= 0

    from = @position
    dry = fade(@bank.block(from, count), from)
    wet = chain(dry, from)
    @position += count
    wet
  end

  # ------------------------------------------------------------- the source
  def build_source
    entries = []
    stems = []
    @plan.parts.each do |part|
      if part.voice['family'] == 'fluid'
        level = 10.0**(part.voice.fetch('gain', 0.0) / 20.0)
        stems << [Fluid.render(part.plucks, part.voice), level * part.gain]
        next
      end
      swell = part.swell && swell_proc(*part.swell)
      step = 15.0 / @bpm
      part.plucks.each do |p|
        notes = Array(p.midi)
        notes.each do |midi|
          start = [((p.base + p.off.clamp(-MAX_OFFSET, MAX_OFFSET)) * SAMPLE_RATE).to_i, 0].max
          make = lambda do
            Voices.reader(part.voice, midi, p.dur, 0.22 * p.gain / Math.sqrt(notes.size), velocity: p.gain, detune: @seq.detune,
                                                                                    step:, registration: part.voice['registration'])
          end
          entries << Stream::Bank::Entry.new(start, make, part.gain, swell)
        end
      end
    end
    stems.each { |samples, level| entries << Stream::Bank::Entry.new(0, -> { Voices::Reader.of(samples) }, level, nil) }
    @bank = Stream::Bank.new(entries)
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
  def fade(block, from)
    return block if @fade_in.zero? && @fade_out.zero? && from + block.size <= @source_end

    block.each_with_index.map do |v, i|
      at = from + i
      gain = 1.0
      gain = Math.sin(Math::PI / 2 * at / @fade_in) if at < @fade_in
      if at >= @source_end then gain = 0.0
      elsif @fade_out.positive? && at >= @source_end - @fade_out then gain *= Math.cos(Math::PI / 2 * (at - (@source_end - @fade_out)) / @fade_out)
      end
      v * gain
    end
  end

  # ------------------------------------------------------------- the effects
  def build_chain
    options = @options
    seq = @seq
    seed = @plan.seed
    @vcs = seq.vcs_amount(options[:vcs])
    sonitex = seq.sonitex_settings(options[:sonitex], instances: options[:sonitex_instances])
    @sonitex = sonitex && Stream::SonitexStack.new(sonitex.fetch('preset'), sonitex.fetch('instances'), seed)
    @drum_sonitex_settings = seq.sonitex_settings(options[:drum_sonitex], instances: options[:drum_sonitex_instances]) || sonitex
    @colour_vcs = Stream::Vcs.new(@vcs)
    echo = seq.echo_settings(flag: options[:echo], mix: options[:echo_mix], feedback: options[:echo_feedback], time_ms: options[:echo_time])
    echo['tail'] = options[:echo_tail] if echo && options[:echo_tail]
    echo['reverb'] = options[:echo_reverb] unless !echo || options[:echo_reverb].nil?
    @echo = echo && echo_line(echo)
    @tail = echo ? (echo.fetch('tail', 4.0) * SAMPLE_RATE).to_i : 0
    texture = @plan.profile_row['texture'] || {}
    @texture = [Stream::Lowpass.new(texture['lowpass']), Stream::Reverb.new(texture['reverb']), Stream::Spring.new(texture['spring'])]
  end

  def echo_line(settings)
    delay = settings['time_ms'] ? settings['time_ms'] / 1000.0 : settings.fetch('time_beats') * 60.0 / @bpm
    resets = (1...@plan.names.size).map { |i| (i * @plan.beats * 60.0 / @bpm * SAMPLE_RATE).round }
    Stream::EchoLine.new(delay:, heads: settings.fetch('heads'), intensity: settings.fetch('intensity'), volume: settings.fetch('echo_volume'),
                         lowpass: settings['lowpass'], saturation: settings.fetch('saturation', 0.0), reverb: settings.fetch('reverb', 0.0),
                         resets:, send: @seq.throws(settings['throws'], @bpm))
  end

  def chain(dry, from)
    out = @sonitex ? @sonitex.process(dry) : dry
    out = @colour_vcs.process(out)
    out = @echo.process(out) if @echo
    out = out.map { |v| v * @chords_gain } if @chords_gain
    out = @duck.apply(out, from) if @duck
    out = @texture.inject(out) { |signal, stage| stage.process(signal) }
    @hits.empty? ? out : mix_drums(out, from)
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
    sidechain = @plan.profile_row['sidechain']
    amount = sidechain ? sidechain.fetch('amount', 0.0) * seq.pd_amount : 0.0
    @duck = sidechain && !amount.zero? ? Stream::Duck.new(@hits.select { |r, _| r == 'kick' }.map { |_, t| t }, amount, sidechain.fetch('release', 0.15)) : nil
    return if @hits.empty?

    kit = seq.kit_sounds
    @drum_bank = Stream::Bank.new(drum_entries(kit))
    crush = @plan.profile_row['drum_crush']
    @drum_crush = crush && Stream::Crush.new(crush.fetch('bits'), 1.0 / crush.fetch('rate'))
    @rumble_amount = kit && @plan.profile_row.dig('rumble', 'amount')
    @rumble = rumble_chain(kit) if @rumble_amount
    drum_sonitex = @drum_sonitex_settings
    @drum_sonitex = drum_sonitex && Stream::SonitexStack.new(drum_sonitex.fetch('preset'), drum_sonitex.fetch('instances'), @plan.seed + 1)
    @drum_vcs = Stream::Vcs.new(options[:drum_vcs].nil? ? @vcs : options[:drum_vcs].to_f.clamp(0.0, 1.0))
    @master_vcs = Stream::Vcs.new(@vcs * 0.5)
    @separate_bus = @drum_sonitex || @vcs.positive? || @drum_crush || @rumble
  end

  def drum_entries(kit)
    closers = @hits.select { |r, *| r == 'hat' }.map { |_, t, *| t }
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
      Stream::Bank::Entry.new((time * SAMPLE_RATE).to_i, make, gain, nil)
    end
  end

  # The drums enter at equal power over the crossfade, and a dropout holds them at nothing, with
  # ten milliseconds to get there and back so it does not click.
  def drum_level(drums, from)
    ramp = (0.01 * SAMPLE_RATE).round
    target = @drums_gain
    previous = @drums_applied || target
    @drums_applied = target
    return drums if @fade_in.zero? && target == 1.0 && previous == 1.0 && from >= @fade_in

    drums.each_with_index.map do |v, i|
      at = from + i
      gain = at < @fade_in ? Math.sin(Math::PI / 2 * at / @fade_in) : 1.0
      level = i < ramp ? previous + ((target - previous) * i / ramp) : target
      v * gain * level
    end
  end

  # The low end grown from the kicks: a room, a lowpass, drive, two more lowpasses, scaled by a
  # fixed gain found once from a single kick, where a whole render scales by its own peak.
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
    @kick_bank = Stream::Bank.new(kicks.map { |start, sample, v| Stream::Bank::Entry.new(start, -> { Voices::Reader.of(sample) }, v, nil) })
  end

  def mix_drums(chords, from)
    drums = drum_level(@drum_bank.block(from, chords.size), from)
    if @separate_bus
      if @rumble
        grown = @rumble_run.call(@rumble_stages, @kick_bank.block(from, chords.size))
        drums = drums.each_with_index.map { |v, i| v + (grown[i] * @rumble_scale * @rumble_amount) }
      end
      drums = @drum_crush.process(drums) if @drum_crush
      drums = @drum_sonitex.process(drums) if @drum_sonitex
      drums = @drum_vcs.process(drums)
      out = chords.each_with_index.map { |v, i| v + drums[i] }
      out = @master_vcs.process(out)
    else
      out = chords.each_with_index.map { |v, i| v + drums[i] }
    end
    out.map { |v| Colour.soft_limit(v) }
  end
end
