# frozen_string_literal: true

require "monitor"
require_relative "strunk_pass"

module Master
  module Voice
    # MASTER's spoken account of its own work, told as one running story.
    #
    # It listens to the lines the runtime already prints (Trace::Dmesg feeds
    # #observe), keeps the thread of what it has already told, and every few
    # seconds turns the new events into the next one to three sentences. The
    # sentences go to the existing Playback queue, so synthesis, prefetch,
    # interruption and the echo guard are the ones every other utterance uses;
    # there is no second audio pipeline.
    #
    # The words come from the cheapest live lane (Io::LaneSelection, tier from
    # voice.yml) under a strict prompt in data/narration.yml. A reply that
    # invents a number, repeats a sentence, refuses, runs long, lacks content
    # overlap with the events, or claims unsupported success is replaced by a
    # deterministic template. The narrator tells only what the events support.
    #
    # Knobs are in voice.yml under `narration:`. Off: enabled: false there,
    # MASTER_NARRATE=0, or /narrate off. Off means Dmesg speaks its plain line.
    #
    # The same class is the bard when built with voice: :bard: data/bard.yml laid over narration.yml
    # and voice.yml bard: over narration:. The bard is on by default and the one that speaks; off
    # (enabled: false under bard:, MASTER_BARD=0, /bard off) hands the story to the factual narrator.
    class Narrator
      Event = Data.define(:text, :raw, :at, :closing, :finding, :incomplete)

      FALSE_VALUES = %w[0 off false no].freeze
      REFUSAL = /\A(?:i(?:'m| am)? (?:sorry|unable)|i can(?:'|no)t|as an ai\b)/i
      SUCCESS_STATUS = /\b(?:complete(?:d)?|done|finished|success(?:ful|fully)?|verified|passed|fixed|resolved|ready|healthy|clean)\b/i
      NEGATED_SUCCESS_STATUS = /\b(?:not|never|cannot|can't|couldn't|could not|didn't|did not|doesn't|does not|isn't|is not|wasn't|was not|hasn't|has not|haven't|have not|without)\b(?:\W+\w+){0,2}\W+(?:complete(?:d)?|done|finished|success(?:ful|fully)?|verified|passed|fixed|resolved|ready|healthy|clean)\b/i
      GROUNDING_STOP_WORDS = %w[
        a about after all also am an and any are as at be because been before being but by
        can cannot could did do does doing down during each for from had has have he her here him
        his how i if in into is it its just may me might more most my no nor not of off on once
        one only or our out over per same she should so some than that the their them then there
        these they this those through to too under up us very was we were what when where
        which while who why will with within without would you your
        zero two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen
        sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty seventy eighty ninety
        hundred thousand million
      ].freeze
      GROUNDING_CONTEXT_WORDS = %w[
        begin begins beginning event events first latest machine middle next now operation previous
        result results story task thing things work
      ].freeze

      attr_reader :calls, :cost_usd, :beats

      def initialize(config: nil, script: nil, writer: nil, speaker: nil, backlog: nil, audible: nil,
                     clock: nil, env: ENV, autostart: false, voice: :narrator)
        @voice = voice
        @config = config || self.class.load_config(voice)
        @script = script || Script.load(*self.class.script_paths(voice))
        @writer = writer || LaneWriter.new(@config)
        @speaker = speaker || method(:speak_to_playback)
        @backlog = backlog || -> { Playback.backlog }
        @audible = audible || -> { Playback.enabled? && Playback.available? }
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @env = env
        @autostart = autostart
        @lock = Monitor.new
        @cheer = Cheer.new(Master.load_yaml(Master.data_path("bard.yml"), default: {})["cheer"]) if voice == :bard
        @started_at = @clock.call
        @last_cheer_at = 0.0
        @override = nil
        @epoch = 0
        @calls = 0
        @cost_usd = 0.0
        @model_failures = 0
        @model_down_until = 0.0
        @held_until = 0.0
        @sentence_times = []
        reset_task
      end

      class << self
        # The bard's knobs lie over the narrator's; only what differs is written under `bard:`.
        def load_config(voice = :narrator)
          row = Master.load_yaml(Master.data_path("voice.yml"), default: {}) || {}
          narration = row["narration"].is_a?(Hash) ? row["narration"] : {}
          bard = row["bard"].is_a?(Hash) ? row["bard"] : {}
          voice == :bard ? narration.merge(bard) : narration
        end

        # The bard's script lies over the factual one, so the filters have one copy.
        def script_paths(voice = :narrator)
          [Master.data_path("narration.yml"), *(Master.data_path("bard.yml") if voice == :bard)]
        end

        def instance(voice = :narrator) = ((@instances ||= {})[voice] ||= new(voice:, autostart: true))

        def reset_instance!
          @instances&.each_value(&:stop)
          @instances = nil
        end

        # The one teller of the story: the bard when it is on, else the factual narrator, else none.
        def teller
          %i[bard narrator].map { |voice| instance(voice) }.find { |told| told.enabled? && told.audible? }
        end

        # Dmesg asks this per line: is the story the voice for this line?
        def narrating? = !teller.nil?

        def observe(text) = teller&.observe(text) || false

        # The user took the floor: drop what is waiting and stay quiet a while.
        def interrupted! = @instances&.each_value(&:interrupt)

        # A reply is about to be spoken; it says what the pending events would.
        def reply_started! = @instances&.each_value(&:halt!)
      end

      def enabled?
        return @override unless @override.nil?
        return false if FALSE_VALUES.include?(@env["MASTER_NARRATE"].to_s.strip.downcase)
        return false if @voice == :bard && FALSE_VALUES.include?(@env["MASTER_BARD"].to_s.strip.downcase)

        @config["enabled"] == true
      end

      def enable! = (@override = true)

      def disable!
        @override = false
        halt!
      end

      def audible? = @audible.call

      def status
        @lock.synchronize do
          { enabled: enabled?, pending: @pending.size, beats: @beats, told: @story.size, calls: @calls,
            cost_usd: @cost_usd.round(4), max_cost_usd: @config["max_cost_usd"], model: model_usable?(@clock.call),
            sentences_last_minute: recent_sentences(@clock.call) }
        end
      end

      # Takes one printed line. True when it became part of the story.
      def observe(raw)
        return false unless enabled? && audible?
        return false if @script.ignored?(raw.to_s)

        text = Sanitizer.clean(raw, @script)
        return false if text.empty? || @script.gist_of(text).empty?

        now = @clock.call
        accepted = @lock.synchronize do
          # Identical progress lines in the same batch add no information.
          next false if @pending.any? { |event| event.text == text }

          @pending << Event.new(
            text:, raw: raw.to_s, at: now,
            closing: @script.closing?(text), finding: @script.finding?(text),
            incomplete: @script.incomplete?(text),
          )
          @pending.shift while @pending.size > @config.fetch("max_events_per_beat") * 3
          @task_open = true
          @last_event_at = now
          @gaps_in_row = 0
          true
        end
        start if accepted && @autostart
        accepted
      end

      # One step of the story. Returns what it did: :spoken, or why not.
      def tick(now = @clock.call)
        return :off unless enabled?
        return :held if now < @held_until || Playback.external_speaking?

        queued = @backlog.call
        job = @lock.synchronize { plan(now, queued) }
        return job unless job.is_a?(Hash)

        sentences = compose(job, now)
        sentences = fit_rate(sentences, now)
        return :rate if sentences.empty?

        tell(sentences, job, now)
      end

      # Stop at once: nothing pending, no beat in flight is allowed to speak.
      def halt!
        @lock.synchronize do
          @epoch += 1
          @pending.clear
          reset_task
        end
      end

      def interrupt
        halt!
        @held_until = @clock.call + @config.fetch("hold_after_interrupt_s").to_f
      end

      def start
        return if @thread&.alive?

        @stopping = false
        @thread = Thread.new do
          Thread.current.report_on_exception = false
          until @stopping
            begin
              tick
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "Voice::Narrator.tick")
            end
            sleep(@config.fetch("poll_s").to_f)
          end
        end
      end

      def stop
        @stopping = true
        @thread&.kill
        @thread = nil
      end

      private

      def reset_task
        @pending = []
        @story = []
        @beats = 0
        @task_open = false
        @last_event_at = 0.0
        @last_spoken_at = 0.0
        @last_gist = nil
        @gaps_in_row = 0
      end

      # Under the lock: decide whether a beat is due and take its events.
      def plan(now, queued)
        close_idle_task(now)
        return :backlog if queued > @config.fetch("max_backlog")

        kind = due_kind(now) || cheer_kind(now)
        return :wait unless kind
        return :rate if @config.fetch("max_sentences_per_minute") - recent_sentences(now) < 1

        events = %i[gap cheer].include?(kind) ? [] : take_events
        @gaps_in_row += 1 if kind == :gap
        { kind:, events:, epoch: @epoch, number: @beats, story: @story.dup, gist_event: gist_event(kind, events) }
      end

      def due_kind(now)
        if @pending.any?
          waited = now - @pending.first.at
          return nil unless @pending.any?(&:closing) || @pending.any?(&:incomplete) ||
                            waited >= @config.fetch("batch_window_s") || @pending.size >= @config.fetch("max_events_per_beat")
          # Incomplete is terminal, but it must never be narrated as success.
          return :incomplete if @pending.any?(&:incomplete)
          return :closing if @pending.any?(&:closing)
          return :opening if @beats.zero?

          @pending.any?(&:finding) ? :finding : :middle
        elsif @task_open && @beats.positive? && @gaps_in_row < 2 && @last_gist &&
              now - @last_spoken_at >= @config.fetch("max_gap_s")
          :gap
        end
      end

      # Nothing pending and nothing said for a while: the bard may freestyle to lift the listener.
      def cheer_kind(now)
        return unless @cheer&.due?(now, [@started_at, @last_event_at, @last_spoken_at, @last_cheer_at].max)
        return unless @pending.empty? && !@task_open

        :cheer
      end

      def close_idle_task(now)
        return unless @task_open && @pending.empty?
        return unless now - [@last_event_at, @last_spoken_at].max >= @config.fetch("task_idle_s")

        reset_task
      end

      # The events of one beat, oldest first. Over the cap, findings stay and the
      # most recent fill the rest.
      def take_events
        limit = @config.fetch("max_events_per_beat")
        taken = @pending.shift(@pending.size)
        return taken if taken.size <= limit

        keep = taken.select(&:finding).first(limit / 2)
        keep |= taken.last(limit - keep.size)
        taken.select { |event| keep.include?(event) }
      end

      def gist_event(kind, events)
        case kind
        when :closing then events.reverse.find(&:closing) || events.last
        when :incomplete then events.reverse.find(&:incomplete) || events.find(&:finding) || events.last
        when :finding then events.find(&:finding) || events.last
        when :gap then nil
        else events.last
        end
      end

      def compose(job, now)
        return cheer_lines(job, now) if job[:kind] == :cheer

        gist = @script.gist_of(job[:gist_event]&.text || @last_gist)
        text = model_text(job, now) if model_usable?(now)
        sentences = text ? accept(text, job) : []
        sentences = template_sentences(job, gist) if sentences.empty?
        unsaid(sentences)
      end

      # A line already told in this story is not told again: the same status repeated is noise.
      def unsaid(sentences)
        told = @story.map { |sentence| normal(sentence) }
        sentences.reject { |sentence| told.include?(normal(sentence)) }
      end

      def cheer_lines(job, now)
        @last_cheer_at = now
        live = model_usable?(now)
        lines = @cheer.sentences(writer: (@writer if live), script: @script, story: job[:story])
        count_call if live

        lines
      end

      def count_call
        @lock.synchronize do
          @calls += 1
          @cost_usd += @config.fetch("est_cost_per_call_usd")
        end
      end

      def model_usable?(now)
        now >= @model_down_until && @cost_usd + @config.fetch("est_cost_per_call_usd") <= @config.fetch("max_cost_usd")
      end

      def model_text(job, now)
        prompt = format(@script.prompt_template,
                        story: job[:story].empty? ? "(nothing yet)" : job[:story].join(" "),
                        beat: @script.beat_instruction(job[:kind]),
                        sentences: @config.fetch("max_sentences_per_beat"),
                        words: @config.fetch("max_words_per_sentence"),
                        events: numbered(job))
        reply = @writer.call(system: @script.system_prompt, prompt:, max_tokens: @config.fetch("max_tokens"))
        @lock.synchronize do
          @calls += 1
          @cost_usd += @config.fetch("est_cost_per_call_usd")
          @model_failures = 0
        end
        reply
      rescue StandardError => e
        @lock.synchronize do
          @model_failures += 1
          @model_down_until = now + 60 * @model_failures if @model_failures >= 2
        end
        Master::Ground::Swallow.log(e, context: "Voice::Narrator.model")
        nil
      end

      def numbered(job)
        lines = job[:events].map.with_index(1) { |event, index| "#{index}. #{event.text}" }
        lines = ["1. #{@script.gist_of(@last_gist)} (the last thing said; nothing newer)"] if lines.empty? && @last_gist
        lines.join("\n")
      end

      # The model's reply, reduced to sentences it may be allowed to say; empty
      # when any rule is broken, which sends the beat to the template.
      def accept(text, job)
        # Filter narration before validation and playback. Preserve qualifiers
        # such as "could not" because they change the meaning of a finding.
        clean = Master::Voice::StrunkPass.call(Sanitizer.clean(text, @script))
        return [] if clean.empty? || clean.match?(REFUSAL)

        sentences = clean.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?).first(@config.fetch("max_sentences_per_beat"))
        return [] if sentences.empty?
        return [] if sentences.any? { |s| s.split.size > @config.fetch("max_words_per_sentence") * 1.5 }
        return [] unless grounded?(sentences, job)

        told = @story.map { |s| normal(s) }
        sentences.reject { |s| told.include?(normal(s)) }
      end

      # Numbers, substantive wording and completion claims must be supported by
      # the current events or the story already told. Number-only validation let
      # fluent but unrelated narration through; a lexical overlap gate sends those
      # replies to the deterministic event template instead.
      def grounded?(sentences, job)
        current = job[:events].map(&:text).join(" ")
        known = ([current] + job[:story] + [@last_gist.to_s]).join(" ")
        known_numbers = known.scan(/\d+/)
        return false unless sentences.join(" ").scan(/\d+/).all? { |digits| known_numbers.include?(digits) }

        return false if sentences.any? { |sentence| unsupported_success_claim?(sentence, current, job[:kind]) }

        evidence = grounding_terms(known)
        return anchored?(sentences, evidence) if @config["grounding"] == "anchor"

        sentences.all? do |sentence|
          terms = grounding_terms(sentence)
          next false if terms.empty?

          terms.all? { |term| evidence.include?(term) }
        end
      end

      def anchored?(sentences, evidence)
        sentences.any? { |sentence| (grounding_terms(sentence) & evidence).any? }
      end

      def unsupported_success_claim?(sentence, current, kind)
        return false unless sentence.match?(SUCCESS_STATUS)
        return false if sentence.match?(NEGATED_SUCCESS_STATUS)
        return true unless kind == :closing && current.match?(SUCCESS_STATUS)

        false
      end

      def grounding_terms(text)
        text.to_s.downcase.scan(/[a-z]{3,}/).filter_map do |word|
          next if GROUNDING_STOP_WORDS.include?(word) || GROUNDING_CONTEXT_WORDS.include?(word)
          next if @script.register_words.include?(word)

          term = word.sub(/ies\z/, "y").sub(/s\z/, "").sub(/ing\z/, "").sub(/ed\z/, "")
          next if term.length < 3 || GROUNDING_STOP_WORDS.include?(term) || GROUNDING_CONTEXT_WORDS.include?(term)

          term
        end.uniq
      end

      def template_sentences(job, gist)
        line = @script.template(job[:kind], job[:number], gist)
        return [] unless line

        clean = Master::Voice::StrunkPass.call(Sanitizer.clean(line, @script))
        clean.empty? ? [] : [clean]
      end

      def normal(sentence) = sentence.downcase.gsub(/[^a-z0-9 ]/, "").squeeze(" ").strip

      def recent_sentences(now)
        @sentence_times.reject! { |at| now - at >= 60 }
        @sentence_times.size
      end

      def fit_rate(sentences, now)
        room = @lock.synchronize { @config.fetch("max_sentences_per_minute") - recent_sentences(now) }
        sentences.first([room, 0].max)
      end

      def tell(sentences, job, now)
        @lock.synchronize do
          return :halted unless job[:epoch] == @epoch
        end
        told = sentences.select { |sentence| @speaker.call(sentence) }
        @lock.synchronize do
          told.each do |sentence|
            @story << sentence
            @sentence_times << now
          end
          @story.shift while @story.size > @config.fetch("context_sentences")
          @last_spoken_at = now
          if told.any?
            @beats += 1
            @last_gist = job[:gist_event]&.text || @last_gist
          end
          reset_task if told.any? && %i[closing incomplete].include?(job[:kind]) && @pending.none?
        end
        told.empty? ? :echo : :spoken
      end

      def speak_to_playback(sentence)
        Playback.enqueue(sentence, **delivery)
      end

      # Delivery is data: voice.yml's section for this register names the voice, style, rate and pitch.
      def delivery
        { voice: presence(@config["voice"])&.to_sym, style: (presence(@config["style"]) || :neutral).to_sym,
          rate: presence(@config["rate"]), pitch: presence(@config["pitch"]), last: true }.compact
      end

      def presence(value) = value.to_s.strip.empty? ? nil : value.to_s.strip
    end
  end
end
