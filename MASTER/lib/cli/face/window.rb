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
        INTERRUPT = "\u0003"
        QUIT = "\u0004"
        ERASE = %W[\u007f \b].freeze
        EXIT_WORDS = %w[/exit /quit exit quit].freeze
        DIM = "\e[2m"
        PLAIN = "\e[0m"
        # Neutral phosphor keeps the terminal face in the browser's restrained
        # particle-stipple palette.
        ACCENT = "\e[38;2;224;229;238m"
        COOL = "\e[38;2;164;174;190m"

        WORDS = %w[/face face].freeze
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
                       size: -> { Sizing.winsize }, event_bus: nil, size_mode: nil, prompt: nil)
          @turn = turn
          @ear = ear
          @mouth = mouth
          @input = input
          @output = output
          @size = size
          @size_mode = size_mode
          @prompt_provider = prompt
          @prompt_at = nil
          @prompt_text = nil
          @prompt_error_reported = false
          @lock = Mutex.new
          @state = :idle
          law_config = Master::Face::LawField.config
          @law_field_visible = law_config.fetch("terminal_law_ring", true) != false
          toggle = law_config.fetch("terminal_toggle_key", "ctrl-v").to_s
          @law_toggle_key = toggle.casecmp("ctrl-v").zero? ? "\u0016" : toggle
          @law_toggle_label = toggle.casecmp("ctrl-v").zero? ? "Ctrl+V" : toggle
          @level = nil
          @words = [ear.missing, mouth.missing].compact
          @draft = +""
          @closing = false
          @retain_input_on_interrupt = false
          @speech_interrupted = false
          @motion = Motion.new(seed: ::Random.new_seed % 1_000_003)
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
        rescue EOFError, IOError, SystemCallError
          "face0: terminal closed"
        ensure
          # Shutdown is a lifecycle boundary for every reader and painter.
          # Stop microphone capture cooperatively; then bound joins so a closed
          # tty cannot leave an orphaned thread behind.
          @closing = true
          @halt_ear = true
          hearing = @hearing
          if hearing&.alive?
            hearing.join(0.25)
            hearing.kill if hearing.alive?
            hearing.join(0.1)
          end
          if painter&.alive?
            painter.kill
            painter.join(0.1)
          end
          unsubscribe_from_bus
          begin
            @output.print("#{PLAIN}\e[?25h\e[?1049l")
            @output.flush
          rescue IOError, SystemCallError
            # Terminal restoration is best-effort after its descriptor closes.
            nil
          end
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
          face_rows, face_cols = Sizing.fit(content_rows, cols, mode: @size_mode || Sizing.mode)
          face = Face.frame(
            state:,
            rows: face_rows,
            cols: face_cols,
            t:,
            level:,
            events:,
            motion: @motion,
            heard: user_speaking?(state),
            viseme: current_viseme,
            color: @output.respond_to?(:tty?) && @output.tty? && ENV["NO_COLOR"] != "1",
            show_laws: @law_field_visible,
          ).split("\n")

          transcript = tail(column(jobs, words), transcript_rows, cols).map do |line|
            line.empty? ? line : "#{DIM}#{line}#{PLAIN}"
          end
          color = @output.respond_to?(:tty?) && @output.tty? && ENV["NO_COLOR"] != "1"

          body = [
            heading(state, color:),
            *stage(face, content_rows).map { |line| center_line(line, cols) },
            *transcript,
            "#{DIM}#{status(state)[0, cols]}#{PLAIN}",
            prompt_line(draft, cols, color:),
          ]
          # The cursor goes where the prompt was drawn; the body is a line short of
          # the window, so the prompt is not on the last row.
          prompt_row = [body.length, rows].min
          body = body.first(rows)
          body += Array.new(rows - body.length, "") if body.length < rows

          painted = body.each_with_index.map do |line, i|
            "\e[#{i + 1};1H#{line}\e[K"
          end.join
          cursor_column = [draft.length + operator_prompt.length + 2, cols].min
          "\e[?25l#{painted}\e[#{prompt_row};#{cursor_column}H\e[?25h"
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
        rescue IOError, SystemCallError
          @closing = true
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
        # The user is speaking while recogniser partials keep arriving, and only
        # when the mic cannot be hearing MASTER (Policy.echo_safe?). The terminal
        # listens between utterances, so the check holds, and it stays the one
        # place that says so.
        def user_speaking?(state)
          return false unless @heard_at && state == :listening
          return false unless Master::Voice::Policy.echo_safe?(playing: false)

          hold = Master::Voice::Policy.awareness.fetch("heard_hold_ms", 1200) / 1000.0
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - @heard_at < hold
        end

        # The reply's own letters, one per syllable onset in the audio envelope:
        # the same letter-to-viseme rule the browser applies (Policy.viseme_for).
        # Between onsets the last shape holds; a quiet frame returns it to neutral.
        def advance_viseme(level)
          onset = level > 0.3 && (@prev_level || 0.0) <= 0.3
          @prev_level = level
          return @viseme = "neutral" if level < 0.05
          return unless onset

          letters = @spoken_letters ||= []
          @viseme = Master::Voice::Policy.viseme_for(letters.shift) unless letters.empty?
        end

        def current_viseme = @viseme || "neutral"

        # The microphone opens on Tab (push to talk). It arms by itself only when face_auto_mic is on (the data,
        # or MASTER_FACE_AUTO_MIC=1), and then never while the beat or the voice is playing, so it does not
        # hear MASTER and answer itself.
        def arm_ear(forced: false)
          return unless @ear.available?
          return unless forced || auto_mic?
          return if @hearing
          return if @ear_after && Process.clock_gettime(Process::CLOCK_MONOTONIC) < @ear_after
          return unless @lock.synchronize { @state == :idle && @draft.empty? }

          @halt_ear = false
          @hearing = Thread.new { hear }
        end

        def hear
          heard = listen
          if heard && !@closing
            if @suppress_heard
              message = @retain_input_on_interrupt ? "listening interrupted — typed input retained" : "listening interrupted"
              set(:idle, [message])
            else
              answer(heard)
            end
          end
        ensure
          @suppress_heard = false
          @retain_input_on_interrupt = false
          @hearing = nil
          @ear_after = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.5
        end

        def react(key)
          return @closing = true if key == :eof || key == QUIT
          return interrupt if key == INTERRUPT
          # Display controls remain usable while the mic is armed; ordinary
          # keys still interrupt capture and become the start of the prompt.
          return toggle_law_field if key == @law_toggle_key
          return interrupt_ear(key) if hearing?
          return arm_ear(forced: true) if key == "\t"

          nudge(:key)
          return submit if ENTER.include?(key)
          return change { @draft.clear } if key == "\u0015"
          return change { @draft.sub!(/\s*\S+\s*\z/, "") || @draft.clear } if key == "\u0017"
          return @output.print("\e[2J\e[H") if key == "\u000c"
          return change { @draft.chop! } if ERASE.include?(key)

          change { @draft << key } if key.match?(/\A[[:print:]]\z/)
        end

        # Ctrl-C cancels current activity or clears a draft; it never closes the face.
        def interrupt
          nudge(:key)
          if hearing?
            @halt_ear = true
            @suppress_heard = true
            @retain_input_on_interrupt = false
            show(["microphone interrupted"])
          elsif @draft.empty?
            show(["interrupted — ready for input; Ctrl-D leaves the face"])
          else
            change { @draft.clear }
            show(["draft cleared"])
          end
        end

        def toggle_law_field
          if Master::Face::LawField.config.fetch("terminal_law_ring", true) == false
            show(["constitutional law glyphs disabled by laws.yml"])
            return
          end

          @law_field_visible = !@law_field_visible
          nudge(:key)
          state = "constitutional law glyphs #{@law_field_visible ? "visible" : "hidden"}"
          if @law_field_visible
            legend = Master::Face::LawField.laws.map do |law|
              "#{law.fetch("glyph")} #{law.fetch("id").to_s.downcase.split("_").first}"
            end.join(" ")
            state = "#{state}: #{legend}" unless legend.empty?
          end
          show([state])
        end

        def hearing? = @hearing&.alive?

        # Hands free is the data default: the face listens when idle, ends a take on silence and answers without
        # Enter. It holds off while MASTER speaks (the face's voice, the speech queue, a bed the bard started), so
        # it does not hear itself. The quiet Dilla chord bed plays under listening.
        def auto_mic?
          return false if Master::Voice::Bed.foreground? || Master::Voice::Playback.backlog.positive?
          return false if Master::Voice::Playback.external_speaking?

          auto_mic_setting?
        end

        def auto_mic_setting?
          return false if ENV["MASTER_FACE_AUTO_MIC"] == "0"

          ENV["MASTER_FACE_AUTO_MIC"] == "1" || Master.patterns_config.fetch("cli", {})["face_auto_mic"] == true
        end

        def mic_label
          return "mic off" unless @ear.available?

          hearing? || auto_mic_setting? ? "mic on" : "mic ready, Tab to talk"
        end

        # Enter ends the take and sends what was heard. A letter ends it too,
        # and that letter is the start of a typed line instead.
        def interrupt_ear(key)
          @halt_ear = true
          return if ENTER.include?(key)

          @suppress_heard = true
          if key.match?(/\A[[:print:]]\z/)
            @retain_input_on_interrupt = true
            change { @draft << key }
          end
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
          unless @ear.available?
            show([@ear.missing])
            return
          end

          set(:listening, ["listening — say stop or type to interrupt"])
          nudge(:listen)
          heard = @ear.listen(
            stop: -> { @halt_ear || @closing },
            on_partial: ->(text) { @heard_at = Process.clock_gettime(Process::CLOCK_MONOTONIC); show(["heard: #{text}"]) }
          )
          if @halt_ear && @suppress_heard
            message = @retain_input_on_interrupt ? "listening interrupted — typed input retained" : "listening interrupted"
            set(:idle, [message])
            return
          end

          heard = heard.to_s.strip
          heard = nil if heard.empty?
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
            @speech_interrupted = false
            set(:speaking, [reply])
            @spoken_letters = reply.downcase.scan(/[aeiou]+|[mbpfwv]/).map { |group| group[0] }
            spoken = @mouth.say(reply, on_level: ->(level) { change { @level = level; advance_viseme(level) } },
                               on_chunk: ->(part) { show([part]) }, stop: -> { stop_key? })
            unless spoken
              message = if @closing
                          "voice0: speech stopped while leaving face"
                        elsif @speech_interrupted
                          "voice0: speech interrupted — reply remains visible"
                        else
                          detail = @mouth.last_error || "audio did not play"
                          "voice0: speech failed — reply shown as text (#{detail})"
                        end
              @speech_interrupted = false
              set(:idle, [reply, message])
              return
            end
            @speech_interrupted = false
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
          if @closing
            Master::Result.err("face0: turn cancelled — leaving face", category: :timeout)
          else
            Master::Result.err("face0: turn interrupted — ready for input", category: :abort)
          end
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
          if key == :eof || key == QUIT
            @closing = true
            return true
          end
          if key == INTERRUPT
            @speech_interrupted = true
            return true
          end

          ENTER.include?(key) || @closing
        end

        # Ctrl-C cancels an active turn without closing the stage; Ctrl-D leaves.
        def cancel_key?
          key = read_key(0)
          if key == :eof || key == QUIT
            @closing = true
            true
          elsif key == INTERRUPT
            true
          else
            false
          end
        end

        # A key, :eof when the input is gone, or nil when none came in time.
        # getc waits on a cooked buffer and drops keys once the terminal is
        # raw. getch reads the tty itself, one character at a time.
        def read_key(timeout)
          return if @input.respond_to?(:wait_readable) && !@input.wait_readable(timeout)

          key = @input.getch
          key.nil? ? :eof : key
        rescue EOFError, IOError, SystemCallError
          # A stream can close after readiness polling but before getch.
          # Treat it as EOF so every consumer follows the normal leave path.
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
                   when /\Atts:anticipate\z/ then :anticipate
                   end
          nudge(motion) if motion
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "face.window.bus_event", event: type)
        end

        def unsubscribe_from_bus
          @event_unsubscribers.each(&:call)
          @event_unsubscribers.clear
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "face.window.unsubscribe")
        end
        def change(&) = @lock.synchronize(&)

        def heading(state, color:)
          mic = mic_label
          label = "MASTER face0 at master0: #{state}, #{mic}"
          return label unless color

          "#{ACCENT}MASTER#{PLAIN} #{DIM}face0 at master0:#{PLAIN} #{COOL}#{state}#{PLAIN}#{DIM},#{PLAIN} #{COOL}#{mic}#{PLAIN}"
        end

        def status(state)
          mic = mic_label
          "#{state}, #{mic}, #{@law_toggle_label} laws, Enter sends, Ctrl-C interrupts/clears, Ctrl-D leaves"
        end

        def prompt_line(draft, cols, color:)
          line = typed(draft, cols)
          token = "#{operator_prompt} "
          return line unless color && line.start_with?(token)

          "#{ACCENT}#{token}#{PLAIN}#{line.delete_prefix(token)}"
        end

        # Isolated callers get a usable fallback; production faces use the exact live REPL prompt.
        # Cache it briefly
        # because the face paints faster than the Git/status prompt needs refreshing.
        def operator_prompt
          return fallback_operator_prompt unless @prompt_provider

          current = now
          return @prompt_text if @prompt_text && @prompt_at && current - @prompt_at < 0.25

          value = @prompt_provider.call.to_s.strip
          @prompt_at = current
          @prompt_text = value.empty? ? fallback_operator_prompt : value
        rescue StandardError => e
          unless @prompt_error_reported
            Master::Ground::Swallow.log(e, context: "face.window.prompt")
            @prompt_error_reported = true
          end
          fallback_operator_prompt
        end

        def fallback_operator_prompt
          Master::Face::Contract.shell_prompt(path: Dir.pwd, root: Master::ROOT)
        end

        # The end of the line being typed, which is the part being typed into.
        def typed(draft, cols)
          line = "#{operator_prompt} #{draft}"
          line.length > cols ? line[-cols..] : line
        end

        # The face centred in the rows the window gives it, when it is smaller
        # (a chosen size), so the strip below keeps its place.
        def stage(face, rows)
          lines = face.first(rows)
          gap = rows - lines.size
          [""] * (gap / 2) + lines + [""] * (gap - (gap / 2))
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
          Array(words).each do |word|
            live = word.to_s.strip
            lines << live if !live.empty? && lines.last != live
          end
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
