# frozen_string_literal: true

# -------------------------------------------------------------------- show
# --play: passes drawn from the bags, each streamed block by block into the player, one beginning
# under the last beat of the one before so the music never stops. A worker thread keeps the
# next pass built ahead of time and another keeps blocks rendered ahead of the player; the
# pipe to the player is what paces them. The master stage, the tape stack and the ceiling,
# runs once over the sum, so it is not restarted at a join.
class Show
  Slot = Struct.new(:streamer, :start)

  FIRST_BLOCK_BEATS = 1 # the first block is one beat, so the music starts before a bar is ready
  BLOCK_BEATS = 4       # then one bar at a time
  LOOKAHEAD = 2         # blocks rendered ahead of the one being played

  attr_reader :stats, :joins, :streamers # joins: the sample each pass begins at

  def initialize(data, options, player:, out: $stdout)
    @data = data
    @options = options
    @player = player
    @out = out
    @rng = Random.new(options[:seed] || Random.new_seed)
    @dir = options[:out] ? File.dirname(options[:out]) : 'out/play'
    FileUtils.mkdir_p(@dir)
    @state_path = File.join(@dir, 'play_state.json')
    state = (JSON.parse(File.read(@state_path)) rescue {})
    @playlist = Playlist.new(data, @rng, state, pool: options[:pool] || 'essential')
    @passes = options[:passes] || Float::INFINITY
    @made = 0
    @stop = false
    @joins = [0]
    @streamers = []
    @stats = { blocks: 0, audio: 0.0, render: 0.0, underruns: 0 }
    tape = data.fetch('tape')
    instances = options.fetch(:tape, tape.fetch('instances'))
    @tape = instances.positive? ? Tape::Stack.new(instances:, drive: options[:tape_drive] || tape.fetch('drive'), seed: options[:seed] || 0, config: tape) : nil
    @ceiling = tape.fetch('ceiling', 0.97)
  end

  # Ask the show to end after the block in hand.
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

  def build_pass(fade_in)
    @made += 1
    pick = @playlist.draw(mode: @options[:mode], voice: @options[:voice], profile: @options[:profile], patch_per_chord: @options[:patch_per_chord])
    pass = pass_options(pick, @made)
    @out.puts pass_line(pick, pass, @made)
    File.write(@state_path, JSON.generate(@playlist.to_h))
    Streamer.new(@data, pass, fade_in:, fade_out_beats: 1).tap { |streamer| @streamers << streamer }
  end

  def pass_options(pick, number)
    data = @data
    options = @options
    pass = options.merge(prog: pick[:prog], seed: @rng.rand(1_000_000), profile: pick[:profile], voice: pick[:voice],
                         mode: pick[:mode], random: false, quick: false, play: false)
    pass[:chord_voices] = pick[:voices] if pick[:voices]
    pass[:arp_style] = options[:arp_style] || pick[:style] if pick[:mode] == 'arp'
    pass[:repeat] = options[:repeat] || pick[:style] if pick[:mode] == 'repeat'
    profile_drums = data['groove_profiles'].fetch(pick[:profile])['drums']
    pass[:drums] = options[:drums] == 'rotate' ? pick[:drums] : (options[:drums] || profile_drums)
    pass[:kit] = options[:kit] || (options[:drums] == 'rotate' ? pick[:kit] : nil)
    pass[:pass] = number
    pass
  end

  def pass_line(pick, pass, number)
    "pass #{number}: progression #{pick[:prog]} (#{pick[:position]}) mode=#{pick[:mode]} style=#{pick[:style] || '-'} " \
      "voice=#{pick[:voices]&.join('>') || pick[:voice]} (patch #{pick[:bag] || 'fixed'}) profile=#{pick[:profile]} " \
      "drums=#{Array(pass[:drums]).join(',').then { |d| d.empty? ? '-' : d }} kit=#{pass[:kit] || '-'}"
  end

  def produce(queue)
    slots = [Slot.new(build_pass(0), 0)]
    upcoming = prepare(slots.last)
    global = 0
    size = slots.first.streamer.beat * FIRST_BLOCK_BEATS
    until @stop
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      slots, upcoming = admit(slots, upcoming, global, size)
      break if slots.empty?

      mixed = Array.new(size, 0.0)
      slots.each do |slot|
        offset = [slot.start - global, 0].max
        next if offset >= size

        part = slot.streamer.next_block(size - offset)
        part.each_with_index { |v, i| mixed[offset + i] += v }
      end
      slots.reject! { |slot| slot.streamer.finished? }
      mixed = master(mixed)
      @stats[:render] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      @stats[:audio] += size.to_f / SAMPLE_RATE
      @stats[:blocks] += 1
      queue << mixed
      global += size
      size = slots.first.streamer.beat * BLOCK_BEATS if slots.any?
    end
    queue << :done
  rescue StandardError => e
    @out.puts "show: #{e.class}: #{e.message}"
    queue << :done
  end

  # Build the next pass on a thread while this one plays, so a join finds it ready.
  def prepare(slot)
    return nil if @made >= @passes

    Thread.new { build_pass(slot.streamer.beat) }
  end

  # When the pass in hand is within a beat of its end, the next one starts under it.
  def admit(slots, upcoming, global, size)
    return [slots, upcoming] unless upcoming

    last = slots.last
    due = last.start + last.streamer.source_end - last.streamer.fade_out
    return [slots, upcoming] if due >= global + size

    fresh = Slot.new(upcoming.value, due)
    @joins << due
    [slots + [fresh], prepare(fresh)]
  end

  def master(block)
    block = @tape.process(block) if @tape
    block = Tape.ceiling(block, top: @ceiling) if @tape
    block
  end
end
