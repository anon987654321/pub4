# frozen_string_literal: true

require "io/console"
require "io/wait"
require_relative "../../io/exec"

module Master
  module CLI
    module Face
      # The face is a full-screen terminal stage. It owns the alternate screen,
      # receives the entire viewport, and keeps a quiet control strip at the bottom.
      # The renderer supplies the depth, lighting and camera language.
      #
      # Enter on an empty line listens, Enter again stops; a typed line is sent
      # as it is. Either way the words go through turn, which is TurnRouter —
      # the path bin/master takes — and the reply is spoken and shown.
      class Window
        ENTER = %W[\r \n].freeze
        LEAVE = %W[\u0003 \u0004].freeze
        ERASE = %W[\u007f \b].freeze
        EXIT_WORDS = %w[/exit /quit exit quit].freeze
        ACCENT = "\e[38;2;255;51;68m"
        DIM = "\e[2m"
        PLAIN = "\e[0m"

        WORDS = %w[/face face].freeze
        CONTROL_ROWS = 4
        MESSAGE_FLAGS = %w[-m -p --message --prompt].freeze

        # Whether a command line asks for the face and nothing else: `face`,
        # `/face`, or either after -m, which is how bin/master passes it on.
        def self.asked?(argv)
          words = argv.reject { |arg| MESSAGE_FLAGS.include?(arg) }
          words.size == 1 && WORDS.include?(words.first.strip)
        end

        # What the face says goes through TurnRouter, as a line typed at
        # bin/master does. The container comes from a block called once, on
        # the first utterance, so the face draws before any runtime exists and
        # the boot is paid only by someone who speaks. A reply that streamed
        # is the streamed text, as the session prints it.
        def self.turn(&boot)
          lock = Mutex.new
          container = nil
          lambda do |text|
            lock.synchronize { container ||= boot.call }
            streamed = +""
            result = TurnRouter.call(message: text, container:, on_turn: ->(line) { streamed << line << "\n" })
            return result if streamed.strip.empty? || result.err?

            streamed
          end
        end

        def initialize(turn:, ear: Ear.new, mouth: Mouth.new, input: $stdin, output: $stdout,
                       size: -> { IO.console&.winsize || [24, 80] }, event_bus: nil)
          @turn = turn
          @ear = ear
          @mouth = mouth
          @input = input
          @output = output
          @size = size
          @lock = Mutex.new
          @state = :idle
          @level = nil
          @words = [ear.missing, mouth.missing].compact
          @draft = +""
          @closing = false
          @motion = Motion.new(seed: Random.new_seed % 1_000_003)
          @events = []
          @jobs = []
          @event_bus = event_bus
          @event_unsubscribers = subscribe_to_bus(event_bus)
          @opened = now
        end

        def run
          @output.print("\e[?1049h\e[2J")
          painter = Thread.new { paint_forever }
          raw { converse }
          "face0: closed"
        ensure
          painter&.kill
          unsubscribe_from_bus
          @output.print("#{PLAIN}\e[?25h\e[?1049l")
          @output.flush
        end

        # One whole window as the escape sequences that draw it, t seconds
        # after the window opened. The events since the last frame go to the
        # face once.
        def screen(rows, cols, t)
          state, level, jobs, words, draft, events = @lock.synchronize do
            [@state, @level, @jobs.dup, @words.dup, @draft.dup, @events.slice!(0..)]
          end

          transcript_rows = rows >= 20 ? 3 : 2
          content_rows = [rows - transcript_rows - 4, 1].max
          face = Face.frame(
            state:,
            rows: content_rows,
            cols:,
            t:,
            level:,
            events:,
            motion: @motion,
            color: @output.respond_to?(:tty?) && @output.tty? && ENV["NO_COLOR"] != "1"
          ).split("\n")

          transcript = tail(column(jobs, words), transcript_rows, cols).map do |line|
            line.empty? ? line : "#{DIM}#{line}#{PLAIN}"
          end

          body = [
            "face0 at master0: #{state}#{@ear.available? ? " · mic on" : " · mic off"}",
            *face.first(content_rows).map { |line| center_line(line, cols) },
            *transcript,
            "#{DIM}#{status(state)[0, cols]}#{PLAIN}",
            typed(draft, cols)
          ]
          body = body.first(rows)
          body += Array.new(rows - body.length, "") if body.length < rows

          painted = body.each_with_index.map do |line, i|
            "\e[#{i + 1};1H#{line}\e[K"
          end.join
          cursor_column = [draft.length + Master::Face::Contract.user_token.length + 2, cols].min
          "\e[?25l#{painted}\e[#{rows};#{cursor_column}H\e[?25h"
        end

        private

        def paint_forever
          last = nil
          loop do
            rows, cols = @size.call
            @output.print("\e[2J") if last && last != [rows, cols]
            last = [rows, cols]
            @output.print(screen(rows, cols, now - @opened))
            @output.flush
            sleep 1.0 / Face::FPS
          end
        end

        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def raw(&)
          @input.respond_to?(:tty?) && @input.tty? ? @input.raw(&) : yield
        end

        def converse
          until @closing
            arm_ear
            key = read_key(0.1)
            react(key) if key
          end
        end

        # Idle, with nothing typed, listens on its own. Enter or a typed
        # character stops that take; the keys stay on this thread.
        def arm_ear
          return unless @ear.available?
          return if @hearing
          return if @ear_after && Process.clock_gettime(Process::CLOCK_MONOTONIC) < @ear_after
          return unless @lock.synchronize { @state == :idle && @draft.empty? }

          @halt_ear = false
          @hearing = Thread.new { hear }
        end

        def hear
          heard = listen
          answer(heard) if heard && !@closing && !@suppress_heard
        ensure
          @suppress_heard = false
          @hearing = nil
          @ear_after = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.5
        end

        def react(key)
          return @closing = true if key == :eof || LEAVE.include?(key)
          return interrupt_ear(key) if hearing?

          nudge(:key)
          return submit if ENTER.include?(key)
          return change { @draft.clear } if key == "\u0015"
          return change { @draft.sub!(/\s*\S+\s*\z/, "") || @draft.clear } if key == "\u0017"
          return @output.print("\e[2J\e[H") if key == "\u000c"
          return change { @draft.chop! } if ERASE.include?(key)

          change { @draft << key } if key.match?(/\A[[:print:]]\z/)
        end

        def hearing? = @hearing&.alive?

        # Enter ends the take and sends what was heard. A letter ends it too,
        # and that letter is the start of a typed line instead.
        def interrupt_ear(key)
          @halt_ear = true
          return if ENTER.include?(key)

          @suppress_heard = true
          change { @draft << key } if key.match?(/\A[[:print:]]\z/)
        end

        def submit
          text = @draft.strip
          change { @draft.clear }
          return @closing = true if EXIT_WORDS.include?(text)

          answer(text) if text && !text.empty?
        end

        # Nil when nothing was heard, and the window says so; no guess stands
        # in for a transcription.
        def listen
          @halt_ear = false
          unless @ear.available?
            show([@ear.missing])
            return
          end

          set(:listening, ["listening — say stop or type to interrupt"])
          nudge(:listen)
          heard = @ear.listen(stop: -> { @halt_ear || @closing }, on_partial: ->(text) { show(["heard: #{text}"]) })
          set(:idle, ["heard nothing"]) unless heard
          heard
        rescue StandardError => e
          set(:idle, ["mic0: #{e.message}"])
          nil
        end

        def answer(text)
          set(:thinking, ["you: #{text}"])
          result = think(text)
          if result.is_a?(Master::Result) && result.err?
            set(:idle, [result.message])
            return
          end

          reply = reply_text(result).to_s.strip
          if reply.empty?
            set(:idle, ["talk0: empty reply"])
            return
          end

          if @mouth.available?
            set(:speaking, [reply])
            spoken = @mouth.say(reply, on_level: ->(level) { change { @level = level } },
                               on_chunk: ->(part) { show([part]) }, stop: -> { stop_key? })
            unless spoken
              set(:idle, [@mouth.last_error || "voice0: audio did not play"])
              return
            end
          end
          set(:idle, [reply])
          nudge(:nod)
          picture(text) if text.to_s.split.size >= 4
        end

        # The still is created only after a real reply, so a failed model turn
        # cannot fall through into media work.
        def picture(text)
          set(:thinking, ["picture0: rendering"])
          paths = Master::Io::IdeaPicture.new.write(text)
          set(:idle, ["picture0: saved #{paths[:clip]}"])
        rescue StandardError => e
          set(:idle, ["picture0: failed — #{e.message.to_s[0, 140]}"])
        end

        # The turn runs beside the window so ^C can abandon it. It carries no
        # terminal asker: the fold's y/N question cannot be answered in raw
        # mode, so the face refuses what needs one, as the web face does. The
        # open-face mark stops a spoken "face" from opening a second one.
        def think(text)
          children = Master::Io::Exec::Children.new
          worker = Thread.new do
            Fiber[:master_children] = children
            Fiber[:master_terminal_ask] = nil
            Fiber[:master_face_open] = true
            @turn.call(text)
          rescue StandardError => e
            Master::Result.err("face0: turn failed — #{e.class}: #{e.message}", category: :infrastructure)
          end
          # The worker is asked before the keyboard, so a turn that has already
          # answered is kept even when input has ended.
          until worker.join(0.05)
            next unless cancel_key?

            return cancel_worker(worker, children)
          end
          worker.value
        end

        def cancel_worker(worker, children)
          worker.kill
          children.kill_all
          @event_bus&.publish(
            "user:interrupt", reason: "face", source: "face", children:
          )
          worker.join(1)
          Master::Result.err("face0: turn cancelled", category: :timeout)
        end

        # turn answers with a Result, or with the text it streamed.
        def reply_text(result)
          return result.to_s unless result.is_a?(Master::Result)
          return "error: #{result.message}" if result.err?

          value = result.value
          # Talk answers with a String, which also answers [] and would raise on a Symbol.
          text = value.is_a?(Hash) ? (value[:rendered] || value[:output]) : nil
          (text || value).to_s.strip
        end

        def stop_key?
          key = read_key(0)
          @closing = true if key == :eof || LEAVE.include?(key)
          ENTER.include?(key) || @closing
        end

        # ^C abandons the turn; ^D abandons it and leaves.
        def cancel_key?
          key = read_key(0)
          @closing = true if key == :eof || key == "\u0004"
          key == :eof || LEAVE.include?(key)
        end

        # A key, :eof when the input is gone, or nil when none came in time.
        # getc waits on a cooked buffer and drops keys once the terminal is
        # raw. getch reads the tty itself, one character at a time.
        def read_key(timeout)
          return if @input.respond_to?(:wait_readable) && !@input.wait_readable(timeout)

          key = @input.getch
          key.nil? ? :eof : key
        rescue EOFError
          :eof
        end

        def set(state, words)
          change do
            @state = state
            @level = nil
            @words = words
            note_job(words)
          end
        end

        # The column under the head. The step that is running is the line,
        # and only the last three stay.
        def note_job(words)
          line = words.first.to_s.strip
          return if line.empty? || @jobs.last == line

          @jobs << line
          @jobs.shift while @jobs.size > 3
        end

        def show(words) = change { @words = words }

        # Something the face reacts to on its next frame (Motion::EVENTS).
        def nudge(event) = change { @events << event }

        # The terminal face listens to the same runtime event families as the
        # browser face. Event delivery only queues a bounded motion event; the
        # painter consumes it on the next frame, so bus handlers never touch the
        # terminal or block a publisher.
        def subscribe_to_bus(event_bus)
          return [] unless event_bus.respond_to?(:subscribe)

          %w[llm:** pipeline:** phantom:** council:** tts:**].map do |pattern|
            event_bus.subscribe(pattern) { |event| bus_event(event) }
          end
        rescue StandardError => e
          set(:idle, ["face0: event bus unavailable — #{e.message.to_s[0, 100]}"])
          []
        end

        def bus_event(event)
          type = event[:event] || event["event"]
          motion = case type.to_s
                   when /\Allm:(?:request|send)\z/, /\Apipeline:stage_start\z/ then :thinking
                   when /\Allm:(?:response|call_complete)\z/, /\Apipeline:(?:stage_complete|complete|done)\z/ then :nod
                   when /\Aphantom:(?:detected|recovery|halt|occurrence)\z/ then :phantom
                   when /\Acouncil:/ then :council
                   end
          nudge(motion) if motion
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "face.window.bus_event", event: type)
        end

        def unsubscribe_from_bus
          @event_unsubscribers.each { |unsubscribe| unsubscribe.call }
          @event_unsubscribers.clear
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "face.window.unsubscribe")
        end
        def change(&) = @lock.synchronize(&)

        def tint(state, line) = state == :listening ? "#{ACCENT}#{line}#{PLAIN}" : line

        def status(state)
          mic = @ear.available? ? "mic on" : "mic off"
          "#{state}, #{mic}, Enter sends, Ctrl-C interrupts, Ctrl-D quits"
        end

        # The end of the line being typed, which is the part being typed into.
        def typed(draft, cols)
          line = "#{Master::Face::Contract.user_token} #{draft}"
          line.length > cols ? line[-cols..] : line
        end

        def center_line(line, cols)
          visible = line.to_s.gsub(/\e\[[0-9;?]*[ -\/]*[@-~]/, "").length
          line.to_s.rjust(line.to_s.length + [(cols - visible) / 2, 0].max)
        end

        # The last rows of the words, wrapped to the window and padded so the
        # status line stays put.
        # The last three lines under the head: finished steps, then the line
        # that is still changing (a partial, a spoken chunk).
        def column(jobs, words)
          lines = jobs.dup
          live = words.first.to_s.strip
          lines << live if !live.empty? && lines.last != live
          lines.last(3)
        end

        def tail(words, rows, cols)
          lines = words.flat_map { |text| wrap(text.to_s, cols) }.last(rows)
          lines + Array.new(rows - lines.size, "")
        end

        def wrap(text, cols)
          text.split("\n").flat_map do |para|
            para.scan(/\S.{0,#{[cols - 1, 1].max}}(?=\s|\z)|\S{#{cols}}/).map(&:strip)
          end
        end
      end
    end
  end
end
