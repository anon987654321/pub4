# frozen_string_literal: true

require "tty-screen"
require_relative "../stream_accumulator"
require_relative "../../voice/typography"

module Master
  module CLI
    class Session
      TICK_SECONDS = 0.20
      SPINNER_FRAMES = ["*", "+", "x", "+"].freeze
      STAGE_EVENTS = {
        "infer:resolved" => "infer",
        "infer:confidence" => "infer",
        "infer:rejected" => "infer",
        "route:resolved" => "route",
        "llm:routed" => "model",
      }.freeze

      private

      # One line that repaints while a turn runs, and above it the turn as a
      # dmesg: each model call, file, command and request the turn makes, as a
      # unit attached to its parent. Routine bus events stay in the event log;
      # one /review publishes about 28,700 of them.
      # The spinner may use the reserved row only while the prompt and draft
      # fit on one physical terminal row. Long drafts disable row painting rather
      # than risk cursor motion into text owned by Reline.
      def activity_row_safe_to_draw?
        return false unless @activity_row_reserved && @reading_input
        return false unless $stdin.tty? && $stdout.tty?

        width = TTY::Screen.width.to_i
        buffer = Reline.line_buffer.to_s
        prompt = @active_prompt.to_s
        width.positive? && prompt.length + buffer.length * 2 + 2 < width
      rescue StandardError
        false
      end

      # Called under Dmesg's terminal mutex. Save and restore the input cursor
      # while clearing the preceding row; if the draft wraps, abandon the row.
      def clear_reserved_activity_row(target)
        return false unless @activity_row_reserved

        safe = activity_row_safe_to_draw? && target.respond_to?(:tty?) && target.tty?
        if safe
          target.print("\e7\e[1A\r\e[K\e8")
          target.flush if target.respond_to?(:flush)
        end
        @activity_row_reserved = false
        safe
      rescue StandardError => e
        @activity_row_reserved = false
        Master::Ground::Swallow.log(e, context: "cli.activity_row.clear", event_bus: @refs.bus)
        false
      end

      def print_thinking_indicator
        init_thinking_state!
        return unless $stdout.tty?

        @spin_thread = Thread.new do
          frame = 0

          loop do
            paused = false
            Master::Trace::Dmesg.terminal_write do |target|
              paused, stage = @think_mutex.synchronize { [@think_paused, @think_stage.to_s] }
              unless paused
                stage = "working" if stage.empty?
                line = one_row("#{SPINNER_FRAMES.fetch(frame % SPINNER_FRAMES.length)} #{stage} #{elapsed_seconds}s")
                if @reading_input
                  # A reserved row above Reline's prompt keeps the animation
                  # visible without painting over the user's editable draft.
                  target.print("\e7\e[1A\r\e[K#{line}\e8") if activity_row_safe_to_draw?
                elsif !@turn_current_started
                  target.print("\r\e[K#{line}")
                end
                target.flush
              end
            end
            break if paused

            frame += 1
            sleep TICK_SECONDS
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.spinner", event_bus: @refs.bus)
        end
      end

      def init_thinking_state!
        @think_mutex = Mutex.new
        @think_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @think_paused = false
        @think_stage = "intake"
        @activity&.reset!
        # `**`: a single star is colon-free names only, and every stage event has one.
        @think_sub = @refs.bus&.subscribe("**") { |payload| update_think_stage(payload) }
        @unit_sub = @refs.logging.listen { |line| print_unit_line(line) } if units_console?
      end

      # The fold stops to ask a person about a push, a hard reset or a deploy,
      # and a terminal the operator is typing into is a person. The operator
      # said approval belongs there, so the interactive session answers; the
      # daemon, a pipe and the web face build no asker and still refuse.
      #
      # Carried as a fiber local because the turn runs on its own thread and
      # CoreBridge builds the World deep below it. A thread spawned inside the
      # turn inherits fiber storage, so the asker answers only on the thread
      # the turn owns: a standing order firing mid-turn runs unattended and is
      # refused, as it is everywhere else.
      def terminal_ask(owner)
        return unless $stdin.tty? && $stdout.tty?

        lambda do |prompt:, options: nil, **|
          next "no: asked off the terminal turn" unless Thread.current == owner

          answer_at_terminal(prompt, options:)
        end
      end

      # y/N, with the spinner held still so the question is not painted over.
      # Anything but a yes is a no, which Core::Fold decides.
      # Keep the established direct approval reader for synchronous turns. A
      # background turn must not compete with Reline for stdin, so it refuses
      # an approval-dependent operation safely while the next prompt is active.
      # In an asynchronous interactive turn, Reline remains the sole owner
      # of stdin. Hand approval requests back to the main input loop instead of
      # starting a second reader that can steal a draft.
      def answer_at_terminal(prompt, options: nil)
        choices = normalize_ask_options(options)
        return auto_approved(prompt, choices) if auto_approve?

        if @turn_worker&.alive? && Thread.current == @pipeline_thread && $stdin.tty? && $stdout.tty?
          request = { answer: nil, choices: }
          @terminal_ask_mutex.synchronize { @pending_terminal_ask = request }
          label = @refs.renderer.render("ask0 at fold0: #{prompt}", mode: :dmesg)
          rows = [label, *choices.each_with_index.map { |choice, index| "  #{index + 1}) #{choice.fetch(:name)}" }]
          rows << (choices.empty? ? "enter /approve or /deny; other input stays queued" : "enter /approve N or /deny; other input stays queued")
          terminal_puts(rows.join("\n"))
          answer = @terminal_ask_mutex.synchronize do
            @terminal_ask_cv.wait(@terminal_ask_mutex) while @pending_terminal_ask.equal?(request) && request[:answer].nil?
            request[:answer]
          end
          return answer.to_s.strip if choices.empty?
          index = Integer(answer, exception: false)
          choice = index && choices[index - 1]
          return choice ? choice.fetch(:value).to_s : ""
        end

        @think_mutex&.synchronize { @think_paused = true }
        terminal_print("\r\e[K")
        return answer_choice_at_terminal(prompt, choices) unless choices.empty?
        terminal_print("#{@refs.renderer.render("ask0 at fold0: #{prompt} [y/N]", mode: :dmesg)} ")
        $stdin.gets.to_s.strip
      ensure
        if defined?(request) && request
          @terminal_ask_mutex.synchronize do
            @pending_terminal_ask = nil if @pending_terminal_ask.equal?(request)
            @terminal_ask_cv.broadcast
          end
        end
        @think_mutex&.synchronize { @think_paused = false }
      end

      # The operator decided the session approves on its own; the line stays in the log.
      def auto_approve?
        config = @refs.respond_to?(:config) ? @refs.config : nil
        (config.respond_to?(:fetch) ? config.fetch("auto_approve", true) : true) != false
      end

      def auto_approved(prompt, choices)
        terminal_puts(@refs.renderer.render("ask0 at fold0: approved, #{prompt}", mode: :dmesg))
        return "yes" if choices.empty?

        (choices.find { |choice| choice.fetch(:value) == "approve" } || choices.first).fetch(:value).to_s
      end

      def terminal_ask_pending?
        @terminal_ask_mutex.synchronize { !@pending_terminal_ask.nil? }
      end

      def answer_pending_terminal_ask(line)
        text = line.to_s.strip
        @terminal_ask_mutex.synchronize do
          request = @pending_terminal_ask
          return false unless request

          if text.match?(%r{\A/deny\z}i)
            request[:answer] = "no"
          elsif text.match?(%r{\A/approve(?:\s+.*)?\z}i)
            value = text.sub(%r{\A/approve}i, "").strip
            request[:answer] = value.empty? && request[:choices].empty? ? "yes" : value
          else
            return false
          end
          @terminal_ask_cv.broadcast
          true
        end
      end

      # LLMs may serialize approval choices as an array, a single choice object,
      # or a name => value map. Normalize those shapes before indexing; an
      # unnormalized Hash was enumerated as key/value pairs and raised a
      # Symbol-to-Integer TypeError when the renderer treated an Array as a Hash.
      def normalize_ask_options(options)
        entries = case options
                  when Array then options
                  when Hash
                    if %i[name label value].any? { |key| options.key?(key) || options.key?(key.to_s) }
                      [options]
                    else
                      options.map { |name, value| { name:, value: } }
                    end
                  else []
                  end

        entries.filter_map do |entry|
          case entry
          when Hash
            name = entry[:name] || entry["name"] || entry[:label] || entry["label"]
            value = entry[:value] || entry["value"] || name
            next if name.nil?

            { name: name.to_s, value: value.to_s }
          when String, Symbol
            { name: entry.to_s, value: entry.to_s }
          end
        end
      end

      def answer_choice_at_terminal(prompt, options)
        choices = options.each_with_index.map { |option, index| "#{index + 1}) #{option.fetch(:name)}" }
        terminal_write do |target|
          target.print @refs.renderer.render("ask0 at fold0: #{prompt}", mode: :dmesg)
          target.print "\n  #{choices.join("\n  ")}\n> "
          target.flush
        end
        selected = $stdin.gets.to_s.strip
        index = Integer(selected, exception: false)
        option = index && options[index - 1]
        option ? option.fetch(:value).to_s : ""
      end

      # The spinner stops when a reply streams; detailed events still print.
      def stop_thinking_indicator
        @think_mutex&.synchronize { @think_paused = true }
        @spin_thread&.join
        @spin_thread = nil
        @think_sub&.call
        @think_sub = nil
        if @activity_row_reserved
          Master::Trace::Dmesg.terminal_write { |target| clear_reserved_activity_row(target) }
        elsif $stdout.tty?
          terminal_print("\r\e[K")
        end
      end

      # Detailed dmesg is the default; MASTER_CLI_QUIET=1 is the opt-out.
      def verbose_output?
        ENV["MASTER_CLI_QUIET"] != "1"
      end

      def units_console?
        @refs.logging.respond_to?(:listen) && Master::Trace::Dmesg.enabled?
      end

      def close_unit_console
        @unit_sub&.call
        @unit_sub = nil
      end

      def update_think_stage(payload)
        event = payload[:event].to_s
        @activity&.record(event, payload)
        stage = stage_for(event, payload)
        @think_mutex&.synchronize { @think_stage = stage } if stage
      end

      def stage_for(event, payload)
        return event.delete_prefix("stage:") if event.start_with?("stage:")
        return payload[:stage].to_s.downcase if event == "pipeline:stage_start"

        STAGE_EVENTS[event]
      end

      # What is worth saying out loud while a pass runs. A pass prints hundreds
      # of unit lines and speaking each would be a torrent; these are the ones a
      # person waiting for it would want called out — a reading finished, a pass
      # of repairs counted, the council's verdict, the pass itself ending.
      # Spoken as they happen, so the reply at the end has only its footer left
      # to say instead of the whole log.
      MILESTONE = /\A(?:obs\d+: done|scan\d+: (?:done|pass \d)|fix\d+: pass \d|crit\d+: |review\d+: (?:complete|incomplete))/

      # A pipe keeps stdout for the reply, so the units go to stderr there.
      def print_unit_line(line)
        return unless Master::Trace::Dmesg.enabled?

        Master::Voice::Playback.speak(line) if line.match?(MILESTONE) && !Master::Trace::Dmesg.log_voice_active?
        return unless verbose_output?

        io = $stdout.isatty ? $stdout : $stderr
        @think_mutex&.synchronize { @think_stage = line[/\A[^\s:]+/] }
        Master::Trace::Dmesg.terminal_write(io:) do |target|
          clear_reserved_activity_row(target) if io.equal?($stdout)
          target.print "\r\e[K" if target.tty?
          target.puts @refs.renderer.render(line, mode: :dim)
          target.flush
          redraw_active_input if io.equal?($stdout) && @reading_input
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_unit_line", event_bus: @refs.bus)
      end

      # The spinner repaints with \r\e[K, which clears one row. A line wider
      # than the screen wraps onto a second row that nothing clears, and every
      # tick left another copy behind it. Unit lines are printed once and may
      # wrap. The spinner's own row cuts at a word's edge on one ellipsis.
      def one_row(text)
        width = TTY::Screen.width - 1
        return text unless width.positive? && text.length > width

        Master::Voice::Typography.ellipsis(text, width)
      rescue StandardError
        text
      end

      def elapsed_seconds
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @think_t0.to_f).floor
      end

      def build_stream_handler(buffer, &on_text)
        Master::CLI::StreamAccumulator.new(buffer, &on_text)
      end
    end
  end
end
