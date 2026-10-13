# frozen_string_literal: true

# ------------------------------------------------------------------ moves
# The hand on the desk. A few times a minute, at a bar, one live move is made: the echo is thrown,
# a filter sweeps down and back, the tape is driven harder, the Sonitex climbs from one pass to
# three and down, the room swells, or the drums drop out for a bar. A move is an event with
# a start and a length in bars, not an oscillator; it is drawn from its own seeded stream so
# that it never disturbs the draws of the passes, it is logged, and when it ends the
# parameter it moved is put back exactly.
module Moves
  NAMES = %w[echo_throw filter_sweep tape_ramp sonitex_climb reverb_swell drum_dropout].freeze
  BARS = { 'echo_throw' => 1, 'filter_sweep' => 3, 'tape_ramp' => 3, 'sonitex_climb' => 5, 'reverb_swell' => 3, 'drum_dropout' => 1 }.freeze
  GAP_SECONDS = 6 # at least this long between the end of one move and the start of the next
  THROW = 3.5
  TOP_HZ = 16_000.0
  LOW_HZ = 700.0
  TAPE_PUSH = 1.0
  ROOM_LEVEL = 0.5

  # The master stage after the decks are summed: the sweep, the Sonitex, the room, then the
  # tape stack and the ceiling. Nothing is in the path unless a move asks for it.
  class Master
    def initialize(tape:, ceiling:, preset:, seed:)
      @tape = tape
      @ceiling = ceiling
      @sweep = Stream::SweepLowpass.new
      @climb = Stream::SonitexClimb.new(preset, seed)
      @room = nil
    end

    # `params`: cutoff [from, to], sonitex n, room [from, to], tape factor.
    def process(block, params = {})
      block = @sweep.process(block, *params[:cutoff]) if params[:cutoff]
      block = @climb.process(block, params[:sonitex]) if params[:sonitex]
      if params[:room]
        @room ||= Stream::RoomSend.new
        block = @room.process(block, *params[:room])
      else
        @room = nil
      end
      return block unless @tape

      @tape.drive_scale = params.fetch(:tape, 1.0)
      Tape.ceiling(@tape.process(block), top: @ceiling)
    end
  end

  # Decides when a move starts and what it does to the decks and the master for each block.
  class Hand
    attr_reader :log, :current

    # `per_minute` moves on average; 0 never moves.
    def initialize(seed, per_minute:, out: nil)
      @rng = Random.new(Zlib.crc32("#{seed}:moves"))
      @per_minute = per_minute.to_f
      @out = out
      @log = []
      @current = nil
      @last = nil
      @quiet_until = 0
      @saved = {}
    end

    # Called for each block before it is rendered. `decks` are the streamers sounding, `overlap` is
    # true while two passes are being crossed. Returns the master's parameters for this block.
    def advance(global, size, bar, decks, overlap: false)
      finish(decks, global) if @current && global >= @current[:start] + @current[:length]
      begin_move(global, size, bar, decks) if @current.nil? && !overlap && global >= @quiet_until
      return {} unless @current

      at = ->(g) { ((g - @current[:start]).to_f / @current[:length]).clamp(0.0, 1.0) }
      params(at.call(global), at.call(global + size), decks)
    end

    # End a move in progress and put everything back (the show is over, or a test is done).
    def stop(decks, global = 0)
      finish(decks, global) if @current
    end

    private

    def begin_move(global, size, bar, decks)
      return if @per_minute <= 0

      return unless @rng.rand < @per_minute * (size.to_f / SAMPLE_RATE) / 60.0

      name = (NAMES - [@last]).sample(random: @rng)
      bars = BARS.fetch(name)
      @current = { name:, start: global, length: bars * bar, bars: }
      @last = name
      @log << [name, global, bars]
      @out&.puts("move: #{name} for #{bars} bar#{'s' unless bars == 1} at #{(global.to_f / SAMPLE_RATE).round(1)}s")
      case name
      when 'echo_throw'
        decks.each { |d| (@saved[d.object_id] ||= {})[:boost] = d.echo_boost; d.echo_boost = THROW }
      when 'drum_dropout'
        decks.each { |d| (@saved[d.object_id] ||= {})[:drums] = d.drums_gain; d.drums_gain = 0.0 }
      end
    end

    def finish(decks, global)
      decks.each do |d|
        saved = @saved.delete(d.object_id) or next
        d.echo_boost = saved[:boost] if saved.key?(:boost)
        d.drums_gain = saved[:drums] if saved.key?(:drums)
      end
      @saved.clear
      @quiet_until = global + (GAP_SECONDS * SAMPLE_RATE)
      @current = nil
    end

    # The shape of a move over its length: 0 at the ends, 1 in the middle, held there a while.
    def tent(p) = p < 1.0 / 3 ? p * 3 : (p < 2.0 / 3 ? 1.0 : (1.0 - p) * 3)

    def params(p0, p1, _decks)
      case @current[:name]
      when 'filter_sweep'
        cutoff = ->(p) { TOP_HZ * ((LOW_HZ / TOP_HZ)**tent(p)) }
        { cutoff: [cutoff.call(p0), cutoff.call(p1)] }
      when 'tape_ramp' then { tape: 1.0 + (TAPE_PUSH * tent((p0 + p1) / 2)) }
      when 'sonitex_climb' then { sonitex: [1, 2, 3, 2, 1][([(p0 + p1) / 2 * 5, 4.999].min).floor] }
      when 'reverb_swell' then { room: [ROOM_LEVEL * tent(p0), ROOM_LEVEL * tent(p1)] }
      else {}
      end
    end
  end
end
