# frozen_string_literal: true

require "digest"

module Master::Core
  # Memory — the unified cognitive architecture.
  # It separates memory into three distinct channels:
  # 1. Episodic: What happened in this session (The Trace)
  # 2. Semantic: What is known to be true (The Knowledge)
  # 3. Procedural: How things are done (The Recipes)
  class Memory
    attr_reader :episodic, :semantic, :procedural, :proof

    Entry = Data.define(:role, :text)

    # Context budget in characters. A ~1GB OpenBSD VPS cannot hold a generous
    # transcript alongside an LLM call without the OOM-killer stepping in, so on a
    # constrained host the budget shrinks and compaction runs sooner. This is the
    # whole of the old HostBudget the core needs — the guard rides on Memory's
    # existing compaction, so the Fold gains no new logic. The rest of HostBudget
    # (TTS toggles, pid reaping, shell tips) is CLI accretion that dies with lib.
    GENEROUS_BUDGET = 24_000
    CONSTRAINED_BUDGET = 8_000
    CONSTRAINED_MB = 1_100

    def self.budget_for(total_mb)
      total_mb && total_mb <= CONSTRAINED_MB ? CONSTRAINED_BUDGET : GENEROUS_BUDGET
    end

    def self.host_budget = budget_for(host_memory_mb)

    # Physical memory in MB, or nil when it cannot be told (then we stay generous).
    def self.host_memory_mb
      @host_memory_mb ||= detect_host_memory_mb
    end

    def self.detect_host_memory_mb
      if RUBY_PLATFORM.include?("openbsd")
        bytes = `sysctl -n hw.physmem 2>/dev/null`.to_i
        return bytes / 1_048_576 if bytes.positive?
      end
      if RUBY_PLATFORM.include?("darwin")
        bytes = `sysctl -n hw.memsize 2>/dev/null`.to_i
        return bytes / 1_048_576 if bytes.positive?
      end
      if File.readable?("/proc/meminfo")
        kb = File.readlines("/proc/meminfo").find { |l| l.start_with?("MemTotal:") }&.split&.fetch(1, nil).to_i
        return kb / 1024 if kb&.positive?
      end
      nil
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "Core::Memory.read")
      nil
    end

    # Only host_memory_mb calls it. `private` cannot reach a `def self.` — see
    # CodeMetrics.public_method_count and TODO.md, "The fold spine had never been
    # scanned".
    private_class_method :detect_host_memory_mb

    def initialize(budget: self.class.host_budget, summarize: ->(dropped) { "[\#{dropped.length} earlier steps summarised]" }, risk: :low)
      @entries = []
      @budget = budget
      @summarize = summarize
      @proof = Proof.new(risk:)

      # Initialize Triple Memory Model
      @episodic = Types::Episodic.new(nil) # Will be linked to episode in pipeline
      @semantic = Types::Semantic.new
      @procedural = Types::Procedural.new
    end

    def link_episode(episode)
      @episodic = Types::Episodic.new(episode)
    end

    def seed_from_intent(intent)
      note(:goal, intent.goal)
      note(:approach, intent.approach) if intent.approach
      note(:evidence, intent.evidence_summary) if intent.evidence_summary
      # Proof takes its risk at construction and has no writer; seeding comes
      # before any evidence, so a fresh Proof loses nothing.
      @proof = Proof.new(risk: intent.risk)
      self
    end

    def note(kind, text)
      entry = Entry.new(role: :note, text: "\#{kind}: \#{text}")
      @goal = entry if kind.to_s == "goal"
      @entries << entry
      self
    end

    # The action as its subject, "read lib/x.rb". Effect\#to_s names only the
    # argument keys, so the model saw "read(path)", could not tell which file it
    # had already read, and read it again.
    def record(effect, observation)
      act = act_text(effect)
      obs = observe_text(effect, observation)
      # The same action straight after it failed fails the same way; gemma3:4b
      # asked a surface-less CLI one question four times. Said once, plainly.
      obs = "ERR: this is the action that just failed (\#{obs}). Do something else." if act == @last_act && @last_failed
      @last_act, @last_failed = act, obs.start_with?("ERR")
      @entries << Entry.new(role: :act, text: act)
      @entries << Entry.new(role: :obs, text: obs)
      @proof.record_evidence(effect, observation)
      @proof.mark_council_pass!(detail: observation.message) if effect.verb == :critique && observation.ok?
      self
    end

    # The context the model proposes against, compacted to the budget and
    # closed by the goal and where the proof stands. A small model reads the end
    # of a prompt best, and the goal at the top of a long transcript was the
    # part it lost.
    def context
      compact if size > @budget
      [*@entries, Entry.new(role: :note, text: state_text)]
    end

    private

    # A read of a file whose content is already on the record is not shown
    # again. gemma3:4b read one file five times with STATE saying done was
    # allowed; the repeat now reads as an error that says what to do instead,
    # whichever model made it, and costs no second copy of the file.
    def observe_text(effect, observation)
      text = observation.to_s
      return text unless effect.verb == :read && observation.ok?

      hex = Digest::SHA256.hexdigest(observation.message)[0, 12]
      path = effect.args[:path].to_s
      @read_shas ||= {}
      return repeat_read_text(path) if @read_shas[path] == hex

      @read_shas[path] = hex
      "\#{text} sha256=\#{hex} \#{observation.message.bytesize}b"
    end

    def repeat_read_text(path)
      "ERR: \#{path} is unchanged since you read it, and its content is above. "         "Do not read it again: answer with done, or act on what it says."
    end

    def act_text(effect)
      args = effect.args
      subject = case effect.verb
                when :write then "\#{args[:path]} (\#{args[:content].to_s.lines.size} lines)"
                when :exec then [Array(args[:argv]).join(" "), (" [\#{args[:evidence]}]" if args[:evidence])].join
                when :git then [args[:operation], *Array(args[:paths])].join(" ")
                else args[:path] || args[:text] || args[:prompt] || args[:summary] || args[:scope]
                end
      "\#{effect.verb} \#{subject}".strip
    end

    def state_text
      scope = @proof.scope
      done = scope[:proved] || scope[:answerable] ? "allowed" : "needs exec evidence first"
      read = scope[:read_paths].uniq.last(6)
      ["STATE \#{@goal&.text}", "read: \#{read.empty? ? "nothing yet" : read.join(", ")}",
       "evidence: \#{scope[:evidence]}/\#{Proof::PASS_THRESHOLD}", "done: \#{done}"].join("; ")
    end

    def size = @entries.sum { |e| e.text.length }

    def compact
      keep = []
      total = 0
      @entries.reverse_each do |e|
        # Cut when the next piece would blow the budget. Waiting for a :note
        # after the budget is already exceeded never fires: Fold writes one
        # note (the goal) then only :act/:obs, so the only note is the oldest
        # entry and compact kept every act/obs and dropped only the goal.
        break if !keep.empty? && (total + e.text.length) > @budget

        keep.unshift(e)
        total += e.text.length
      end
      dropped = @entries[0...(@entries.length - keep.length)]
      return if dropped.empty?

      # The goal outlives compaction; everything else old is summarised.
      pinned = dropped.include?(@goal) ? [@goal] : []
      @entries = [*pinned, Entry.new(role: :note, text: @summarize.call(dropped - pinned)), *keep]
    end
  end
end
