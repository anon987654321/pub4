# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Trace
    class Session
      # Save/load the session's durable state to/from disk — separate from
      # Session's own in-memory message/cost/snapshot tracking.
      #
      # This is `.master/session.json`, which is the CLI's transcript: one
      # process, one person, one file. Since Session grew per-conversation
      # partitions it reads and writes the :local partition explicitly rather
      # than whichever conversation happens to be current — a web request must
      # never be able to persist a visitor's transcript to the operator's disk,
      # and load! must not drop a visitor's turns into the operator's history.
      module Persistence
        def save!
          FileUtils.mkdir_p(File.dirname(@path))
          data = {
            name: name(Session::LOCAL),
            phase: @phase,
            topic: @topic,
            last_inferred_command: @last_inferred_command,
            last_inferred_args: @last_inferred_args,
            messages: pruned_messages(Session::LOCAL),
            cost: @cost,
            ts: Time.now.to_i,
          }
          File.write(@path, JSON.generate(data))
        end

        def load!
          return self unless File.exist?(@path)

          begin
            data = JSON.parse(File.read(@path), symbolize_names: true)
            # A valid JSON array or scalar parses and then dies on the first
            # data.fetch below, which reads as a crash in the loader rather than
            # as a damaged file.
            raise JSON::ParserError, "session root is not an object" unless data.is_a?(Hash)
          rescue JSON::ParserError, Errno::ENOENT => e
            quarantine_corrupt_session!(e)
            data = {}
          end
          @phase = data.fetch(:phase, nil)&.to_sym || :discover
          @topic = data[:topic]
          @last_inferred_command = data[:last_inferred_command]
          @last_inferred_args = data[:last_inferred_args]
          @cost = data[:cost].to_f
          # Rebuilt directly rather than replayed through add_message, which
          # would stamp a fresh `ts` on every restored turn and re-derive a name
          # the file already carries. Pinned to :local: this file is the
          # operator's transcript, and loading it must not land in a visitor.
          msgs = Array(data.fetch(:messages, []))
          est = msgs.sum { |m| Session.estimate_tokens(m[:content]) }
          @mutex.synchronize { @conversations[Session::LOCAL] = { messages: msgs, token_est: est, name: data[:name] } }
          self
        end

        private

        # A damaged transcript is renamed, never deleted, and never fatal.
        #
        # The rescue above used to swallow the parse error and continue with an
        # empty hash, so the next save overwrote the file that caused it and the
        # evidence went with it. Now the bytes are kept beside a .reason file
        # naming the error, and startup carries on: a corrupt transcript is not
        # worth refusing to boot over, and it is worth being able to read
        # afterwards.
        def quarantine_corrupt_session!(error)
          stamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
          target = "#{@path}.corrupt.#{stamp}.#{Process.pid}"
          FileUtils.mv(@path, target)
          File.write("#{target}.reason", "#{error.class}: #{error.message}\n")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Session.quarantine_corrupt_session",
                                        severity: :load_bearing, path: @path)
          nil
        end
      end
    end
  end
end
module Master
  module Trace
    class Session
      # In-memory per-path content snapshots (not persisted to disk) —
      # separate from Session's own message/cost/save-load concerns.
      module Snapshots
        def snapshot(path, content)
          @mutex.synchronize do
            @snapshots[path] ||= []
            @snapshots[path] << content
          end
        end

        def last_snapshot(path)
          @mutex.synchronize { @snapshots[path]&.last }
        end
      end
    end
  end
end

module Master
  module Trace
    class Session
      include Persistence
      include Snapshots

      TOKENS_PER_CHAR = 4
      SESSION_NAME_MAX = 40
      # 100 KB session cost log cap
      COSTS_MAX_BYTES = 102_400
      FULL_MESSAGE_WINDOW = 40
      SUMMARY_MAX_CHARS = 240

      # One Session object, many conversations.
      #
      # The container is a process singleton (web/config/initializers/
      # master_container.rb), so before this there was one @messages array for
      # every visitor to ai.brgen.no at once. Agent#conversation_context feeds
      # the model `messages.last(17)`, so a stranger's turns became your
      # context: it could answer you with what someone else had just said, and
      # two people typing at the same time interleaved into one transcript.
      # /chat/history is auth-gated, so the endpoint never leaked — the model
      # did.
      #
      # Absent key means :local, which is the CLI, every test, and any caller
      # that never heard of conversations. One process, one person, unchanged
      # behaviour. Only the web sets the key, and it sets it per request.
      LOCAL = :local

      # The fiber-local exists for the runtime path only, where the caller is
      # Agent#conversation_context several frames down and has no key to pass.
      # Everywhere the caller does know its key — persistence pinning :local, the
      # history endpoint, tests — it passes one, because a fiber-local set and
      # restored around a block is a worse way to say the same thing.
      def self.conversation_key = Fiber[:master_conversation] || LOCAL

      attr_reader :cost, :tokens_billed, :phase, :snapshots, :budget_max
      attr_accessor :topic, :last_inferred_command, :last_inferred_args

      def initialize(root: Dir.pwd, budget_max: 10.0, req_max: 1.0)
        @root = root
        @budget_max = budget_max
        @req_max = req_max
        @mutex = Mutex.new
        @conversations = {}
        @snapshots = {}
        @cost = 0.0
        @tokens_billed = 0
        @phase = :discover
        @topic = nil
        @last_inferred_command = nil
        @last_inferred_args = nil
        @path = File.join(root, ".master", "session.json")
        @costs_path = File.join(root, ".master", "costs.jsonl")
        Dir.mkdir(File.join(root, ".master")) unless Dir.exist?(File.join(root, ".master"))
      end

      # The current conversation's transcript. Returned by reference, not
      # copied: callers append to it (test_llm_dispatcher does) and every
      # existing reader expects the same array identity it always got.
      def messages(key = Session.conversation_key) = @mutex.synchronize { conversation(key)[:messages] }
      def name(key = Session.conversation_key) = @mutex.synchronize { conversation(key)[:name] }

      def add_message(role:, content:)
        msg = { role:, content:, ts: Time.now.to_i }
        @mutex.synchronize do
          conversation[:messages] << msg
          conversation[:token_est] += Session.estimate_tokens(content)
          conversation[:name] ||= auto_name(content) if role == :user
        end
        msg
      end

      def record_cost(amount, model:, tokens:)
        entry = nil
        @mutex.synchronize do
          @cost += amount
          @tokens_billed += tokens.to_i
          entry = { ts: Time.now.to_i, amount:, model:, tokens: tokens.to_i, total: @cost, billed: @tokens_billed }
        end
        rotate_costs! if File.exist?(@costs_path) && File.size(@costs_path) > COSTS_MAX_BYTES
        File.open(@costs_path, "a") { |f| f.puts(JSON.generate(entry)) }
        entry
      end

      def self.estimate_tokens(text) = text.to_s.bytesize / TOKENS_PER_CHAR

      def exists? = File.exist?(@path)

      # Clears the caller's own conversation, not everyone's. Cost is deliberately
      # still global — it is money spent by the process, and no visitor's /clear
      # should zero the operator's spend.
      def clear!
        @mutex.synchronize { @conversations[Session.conversation_key] = blank_conversation; @topic = nil }
        self
      end

      def token_est(key = Session.conversation_key) = @mutex.synchronize { conversation(key)[:token_est] }

      private

      # Always call inside @mutex. Created on read rather than up front, so a key
      # that has never spoken costs nothing.
      def conversation(key = Session.conversation_key) = @conversations[key] ||= blank_conversation

      def blank_conversation = { messages: [], token_est: 0, name: nil }

      def pruned_messages(key = Session.conversation_key)
        @mutex.synchronize do
          msgs = conversation(key)[:messages]
          return msgs if msgs.size <= FULL_MESSAGE_WINDOW

          older = msgs[0...-FULL_MESSAGE_WINDOW]
          recent = msgs.last(FULL_MESSAGE_WINDOW)
          older.map { |msg| summarize_message(msg) } + recent
        end
      end

      def summarize_message(msg)
        content = msg[:content].to_s.gsub(/\s+/, " ").strip
        summary = content.bytesize > SUMMARY_MAX_CHARS ? "#{content.byteslice(0, SUMMARY_MAX_CHARS)}..." : content
        msg.merge(content: "[summary] #{summary}", summarized: true)
      end

      SHELL_CMDS = "cd|ls|pwd|grep|find|cat|echo|export|sudo|doas|git|bundle|ruby|exec|eval|bash|zsh|sh"
      SHELL_RE = /\A(?:#{SHELL_CMDS})\b|[$`|;&]/.freeze

      def auto_name(content)
        stripped = content.to_s.strip
        return Time.now.strftime("%Y%m%d-%H%M") if stripped.match?(SHELL_RE)
        stripped.split.first(5).join(" ")[0, SESSION_NAME_MAX]
      end

      def rotate_costs!
        return unless File.exist?(@costs_path)

        lines = File.readlines(@costs_path)
        keep = lines.last([lines.size / 2, 1].max)
        File.write(@costs_path, keep.join)
      end
    end
  end
end
