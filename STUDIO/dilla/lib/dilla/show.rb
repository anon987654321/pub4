# frozen_string_literal: true

# -------------------------------------------------------------------- show
# --play: passes drawn from the bags, each streamed block by block into the player. With two
# decks, deck B is built, and its first bars rendered, while deck A plays; when A has played its
# eight to sixteen bars B comes in under it, equal power, over two to four bars that begin on A's bar
# line, B's tempo within six beats of A's. The drums keep running: A's go on to the end of its last bar
# and B's come in with the crossfade. With one deck the crossfade is a single beat and every pass is
# its own length. A few times a minute a live move is made (see Moves). The master stage runs
# once over the sum, so a join does not restart it.
class Show
  Slot = Struct.new(:streamer, :start)

  FIRST_BLOCK_BEATS = 1 # the first block is one beat, so the music starts before a bar is ready
  SECOND_BLOCK_BEATS = 3 # the rest of the first bar, so the blocks after it fall on bar lines
  BLOCK_BEATS = 4        # then one bar at a time
  LOOKAHEAD = 2          # blocks rendered ahead of the one being played
  TEMPO_WINDOW = 6.0     # beats a minute either side of the deck that plays
  PASS_BARS = (8..16)
  CROSSFADE_BARS = (2..4)
  MOVES_PER_MINUTE = 3.0

  attr_reader :stats, :joins, :streamers, :hand, :crossfades

  def initialize(data, options, player:, out: $stdout)
    @data = data
    @options = options
    @player = player
    @out = out
    @decks = options.fetch(:decks, 2)
    @rng = Random.new(options[:seed] || Random.new_seed)
    @mix_rng = Random.new(Zlib.crc32("#{options[:seed]}:mix"))
    @dir = options[:out] ? File.dirname(options[:out]) : 'out/play'
    FileUtils.mkdir_p(@dir)
    @state_path = File.join(@dir, 'play_state.json')
    state = (JSON.parse(File.read(@state_path)) rescue {})
    @playlist = Playlist.new(data, @rng, state, pool: options[:pool] || 'essential')
    @passes = options[:passes] || Float::INFINITY
    @made = 0
    @stop = false
    @joins = [0]
    @crossfades = []
    @streamers = []
    @last_bpm = nil
    @stats = { blocks: 0, audio: 0.0, render: 0.0, underruns: 0 }
    tape = data.fetch('tape')
    instances = options.fetch(:tape, tape.fetch('instances'))
    stack = instances.positive? ? Tape::Stack.new(instances:, drive: options[:tape_drive] || tape.fetch('drive'), seed: options[:seed] || 0, config: tape) : nil
    preset = data.dig('sonitex', 'presets').fetch(data.dig('sonitex', 'default'))
    channels = options[:mono] ? 1 : 2
    chain = options[:master] == false ? nil : Mastering::Chain.new(data.fetch('master'), channels:)
    chain&.target = options[:lufs] if options[:lufs]
    @master = Moves::Master.new(tape: stack, ceiling: tape.fetch('ceiling', 0.97), preset:, seed: options[:seed] || 0, instances:,
                                tape_args: { drive: options[:tape_drive] || tape.fetch('drive'), config: tape },
                                imager: options[:mono] ? nil : data.dig('stereo', 'imager'), chain:)
    @dither = Mastering::Dither.new(options[:seed] || 0)
    per_minute = options.fetch(:moves, @decks > 1 ? MOVES_PER_MINUTE : 0.0)
    @hand = Moves::Hand.new(options[:seed] || 0, per_minute:, out:)
  end

  # Ask the show to end after the block in hand, and the player to stop so that a write
  # blocked on a full pipe comes back.
  def stop!
    @stop = true
    @player.interrupt
  end

  def run
    queue = SizedQueue.new(LOOKAHEAD)
    producer = Thread.new { produce(queue) }
    producer.report_on_exception = false
    interrupted = false
    began = nil
    written = 0
    loop do
      starved = queue.empty?
      block = queue.pop(timeout: 0.25)
      if block.nil?
        (interrupted = true) && break if @stop
        next
      end
      break if block == :done

      began ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # late: the player had played everything we gave it and we had nothing more
      @stats[:underruns] += 1 if starved && written.positive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) - began > written.to_f / SAMPLE_RATE
      break unless @player.write(block)

      written += block.size
    end
    interrupted ||= @stop
    @stop = true
    queue.clear
    producer.join(10)
    interrupted ? @player.kill : @player.finish
  ensure
    producer&.kill
  end

  private

  # A pass drawn from the bags. `fade_in` samples, and `fade_out_beats` of this pass's own beats.
  def build_pass(fade_in, fade_out_beats, prefetch: 0)
    @made += 1
    pick = @playlist.draw(mode: @options[:mode], voice: @options[:voice], profile: @options[:profile], patch_per_chord: @options[:patch_per_chord])
    pass = pass_options(pick, @made)
    @out.puts pass_line(pick, pass, @made)
    File.write(@state_path, JSON.generate(@playlist.to_h))
    Streamer.new(@data, pass, fade_in:, fade_out_beats:).tap do |streamer|
      @last_bpm = streamer.plan.bpm
      streamer.prefetch(prefetch) if prefetch.positive?
      @streamers << streamer
    end
  end

  def pass_options(pick, number)
    data = @data
    options = @options
    pass = options.merge(prog: pick[:prog], seed: @rng.rand(1_000_000), profile: pick[:profile], voice: pick[:voice],
                         mode: pick[:mode], random: false, quick: false, play: false)
    pass[:chord_voices] = pick[:voices] if pick[:voices]
    pass[:arp_style] = options[:arp_style] || pick[:style] if pick[:mode] == 'arp'
    pass[:repeat] = options[:repeat] || pick[:style] if pick[:mode] == 'repeat'
    profile_row = data['groove_profiles'].fetch(pick[:profile])
    pass[:drums] = options[:drums] == 'rotate' ? pick[:drums] : (options[:drums] || profile_row['drums'])
    pass[:kit] = options[:kit] || (options[:drums] == 'rotate' ? pick[:kit] : profile_row['kit'])
    pass[:pass] = number
    fit_to_deck(pass, pick) if @decks > 1
    pass
  end

  # A deck's pass lasts eight to sixteen bars, whatever the progression's length, and keeps its
  # tempo within the window of the deck before it.
  def fit_to_deck(pass, pick)
    profile = @data['groove_profiles'].fetch(pick[:profile])
    bars = @mix_rng.rand(PASS_BARS)
    beats = pass[:beats] || profile.fetch('beats', 8.0)
    pass[:bars] = bars
    chords = (bars * 4.0 / beats).round.clamp(2, 16)
    progression = @data.fetch('progressions').fetch(pick[:prog])
    pass[:names] = Array.new(chords) { |i| progression[i % progression.size] }
    bpm = pass[:bpm] || profile.fetch('bpm', 88.0)
    pass[:bpm] = bpm.clamp(@last_bpm - TEMPO_WINDOW, @last_bpm + TEMPO_WINDOW) if @last_bpm
  end

  def pass_line(pick, pass, number)
    "pass #{number}: progression #{pick[:prog]} (#{pick[:position]}) mode=#{pick[:mode]} style=#{pick[:style] || '-'} " \
      "voice=#{pick[:voices]&.join('>') || pick[:voice]} (patch #{pick[:bag] || 'fixed'}) profile=#{pick[:profile]} " \
      "drums=#{Array(pass[:drums]).join(',').then { |d| d.empty? ? '-' : d }} kit=#{pass[:kit] || '-'}" \
      "#{" bpm=#{pass[:bpm]}" if pass[:bpm]}"
  end

  # Beats the crossfade after a pass lasts: whole bars of two to four with two decks, one beat with one.
  def crossfade_beats = @decks > 1 ? @mix_rng.rand(CROSSFADE_BARS) * 4 : 1

  def produce(queue)
    channels = @options[:mono] ? 1 : 2
    first_fade = crossfade_beats
    slots = [Slot.new(build_pass(0, first_fade), 0)]
    @crossfades << first_fade
    upcoming = prepare(slots.last, first_fade)
    global = 0
    openers = [slots.first.streamer.beat * FIRST_BLOCK_BEATS, slots.first.streamer.beat * SECOND_BLOCK_BEATS]
    until @stop || slots.empty?
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      slots, upcoming = admit(slots, upcoming, global, join_at(slots))
      bar = slots.last.streamer.beat * BLOCK_BEATS
      size = openers.shift || bar
      due = join_at(slots)
      size = [size, due - global].min if upcoming && due > global

      params = @hand.advance(global, size, bar, slots.map(&:streamer), overlap: slots.size > 1)
      mixed = Stereo.zeros(channels, size)
      slots.each do |slot|
        offset = [slot.start - global, 0].max
        next if offset >= size

        part = slot.streamer.next_block(size - offset)
        Stereo.add!(mixed, channels == 1 ? [part] : part, offset)
      end
      @master.bpm = slots.last.streamer.plan.bpm
      slots.reject! { |slot| slot.streamer.finished? }
      mixed = @dither.process(@master.process(mixed, params))
      mixed = mixed.first if channels == 1
      spent = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      @stats[:render] += spent
      keep_up(spent / (size.to_f / SAMPLE_RATE))
      @stats[:audio] += size.to_f / SAMPLE_RATE
      @stats[:blocks] += 1
      queue << mixed
      global += size
    end
    @hand.stop(slots.map(&:streamer), global)
    queue << :done
  rescue StandardError => e
    @out.puts "show: #{e.class}: #{e.message}"
    queue << :done
  end

  # The cost of a block against its length, smoothed: past nine tenths the master's dear stages go and the show says so.
  def keep_up(ratio)
    @pace = @pace ? (@pace * 0.8) + (ratio * 0.2) : ratio
    chain = @master.chain
    return unless chain && !chain.light? && @pace > @options.fetch(:pace, 0.9) && @stats[:blocks] > 4

    chain.lighten!
    @out.puts format('master: lightened, the show was rendering at %.2fx real time', @pace)
  end

  # Build the next pass on a thread while this one plays, its first bars rendered ahead so that a
  # crossfade costs no more than a pass alone.
  def prepare(slot, fade_beats)
    return nil if @made >= @passes

    fade_in = fade_beats * slot.streamer.beat
    next_fade = crossfade_beats
    Thread.new do
      streamer = build_pass(fade_in, next_fade, prefetch: fade_in + (slot.streamer.beat * BLOCK_BEATS))
      [streamer, next_fade]
    end
  end

  # The sample at which the next pass begins: where the pass in hand starts its fade-out.
  def join_at(slots)
    last = slots.last
    last.start + last.streamer.source_end - last.streamer.fade_out
  end

  def admit(slots, upcoming, global, due)
    return [slots, upcoming] unless upcoming && due <= global

    streamer, next_fade = upcoming.value
    @joins << due
    @crossfades << next_fade
    fresh = Slot.new(streamer, due)
    [slots + [fresh], prepare(fresh, next_fade)]
  end
end
