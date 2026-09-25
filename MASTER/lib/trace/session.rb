# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "set"

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
        include Master::Io::AtomicWrite

        # Whole or not at all: load! quarantines a transcript it cannot parse,
        # so a save cut short by a crash would cost every turn, not the last.
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
          write_atomic(@path, JSON.generate(data))
          save_forks!
        end

        # No schema_version in the file: it has one shape, every field below is
        # read with a default, and a file that fails to parse is quarantined
        # beside its reason, so a version key has nothing to decide.
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
          load_forks!
          self
        end

        private

        def forks_path = File.join(File.dirname(@path), "conversations.json")

        def save_forks!
          data = @mutex.synchronize do
            @persistent_keys.filter_map do |key|
              conversation = @conversations[key]
              next unless conversation
              [key.to_s, { messages: conversation[:messages], token_est: conversation[:token_est], name: conversation[:name], input_tokens: conversation[:input_tokens] }]
            end.to_h
          end
          write_atomic(forks_path, JSON.generate(data))
        end

        def load_forks!
          return unless File.exist?(forks_path)
          data = JSON.parse(File.read(forks_path))
          raise JSON::ParserError, "conversation root is not an object" unless data.is_a?(Hash)
          @mutex.synchronize do
            data.each do |key, value|
              next unless value.is_a?(Hash)
              messages = value["messages"]
              raise JSON::ParserError, "conversation messages are not an array" unless messages.is_a?(Array)
              # Messages read back with symbol keys, as load! reads session.json;
              # the conversation keys stay strings, which is what fork! and
              # switch! look them up by.
              messages = messages.map { |message| message.is_a?(Hash) ? message.transform_keys(&:to_sym) : message }
              @conversations[key] = { messages:, token_est: value["token_est"].to_i, name: value["name"], input_tokens: value["input_tokens"].to_i }
              @persistent_keys << key
            end
          end
        rescue JSON::ParserError, Errno::ENOENT => e
          quarantine_forks!(e)
        end

        def quarantine_forks!(error)
          stamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
          target = "#{forks_path}.corrupt.#{stamp}.#{Process.pid}"
          FileUtils.mv(forks_path, target)
          File.write("#{target}.reason", "#{error.class}: #{error.message}\n")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Session.quarantine_forks", severity: :load_bearing, path: forks_path)
        end

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
      # In-memory per-path content snapshots (not persisted to disk) —
      # separate from Session's own message/cost/save-load concerns.
      module Snapshots
        def snapshot(path, content)
          @mutex.synchronize do
            @snapshots[path] ||= []
            @snapshots[path] << content
          end
        end
      end

      # Token accounting and compaction of one conversation, which ContextWindow
      # drives — separate from Session's transcript, cost and save-load concerns.
      module Compaction
        def token_est(key = nil) = @mutex.synchronize { conversation(key || current_key)[:token_est] }

        # The provider counts the system prompt, tools and the messages it was
        # sent, which the character estimate never sees, so pressure takes the
        # larger of the two.
        def record_input_tokens(count) = @mutex.synchronize { conversation(current_key)[:input_tokens] = count.to_i }

        def token_pressure(key = nil)
          @mutex.synchronize do
            convo = conversation(key || current_key)
            [convo[:token_est].to_i, convo[:input_tokens].to_i].max
          end
        end

        # Replaces the first `count` messages with one summary, under the mutex,
        # so turns appended while the summary was being written survive it.
        def compact_prefix!(count, summary)
          @mutex.synchronize do
            convo = conversation(current_key)
            kept = convo[:messages].drop(count)
            head = { role: :assistant, content: summary, ts: Time.now.to_i }
            convo[:messages].replace([head] + kept)
            convo[:token_est] = convo[:messages].sum { |msg| Session.estimate_tokens(msg[:content]) }
            convo[:input_tokens] = 0
          end
          self
        end
      end

      # Which conversation is active, and forking and switching between
      # them -- separate from the transcript each conversation holds.
      module Conversations
        def name(key = nil) = @mutex.synchronize { conversation(key || current_key)[:name] }

        # Clone a conversation without changing the caller's active conversation.
        def fork!(source_key: nil, target_key: nil)
          target_key ||= "fork-#{Time.now.utc.strftime("%Y%m%d%H%M%S")}-#{SecureRandom.hex(4)}"
          raise ArgumentError, "source and target conversations are identical" if source_key == target_key
          @mutex.synchronize do
            raise ArgumentError, "conversation already exists: #{target_key}" if @conversations.key?(target_key)
            source = conversation(source_key || current_key)
            @conversations[target_key] = {
              messages: source[:messages].map(&:dup),
              token_est: source[:token_est],
              name: source[:name],
              input_tokens: source[:input_tokens].to_i,
            }
            @persistent_keys << target_key
          end
          target_key
        end

        def conversation_keys
          @mutex.synchronize { @conversations.keys.dup }
        end

        def active_key = @active_key || LOCAL

        def switch!(key)
          key = key.to_s.strip
          raise ArgumentError, "conversation is empty" if key.empty?
          @mutex.synchronize do
            raise ArgumentError, "conversation not found: #{key}" unless @conversations.key?(key)
            @active_key = key
          end
          key
        end
      end

      include Persistence
      include Snapshots
      include Compaction
      include Conversations

      # An estimate, on purpose: the exact count needs tiktoken_ruby, a Rust
      # extension, and this repo deploys to OpenBSD.
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
      # the model `messages.last(41)`, so a stranger's turns became your
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
        @persistent_keys = Set.new
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
      def messages(key = nil) = @mutex.synchronize { conversation(key || current_key)[:messages] }

      def add_message(role:, content:)
        msg = { role:, content:, ts: Time.now.to_i }
        @mutex.synchronize do
          conversation(current_key)[:messages] << msg
          conversation(current_key)[:token_est] += Session.estimate_tokens(content)
          conversation(current_key)[:name] ||= auto_name(content) if role == :user
        end
        msg
      end

      # The row names the model that answered, which after a fallback is not
      # the one routed, and says when the amount is a guess: a model the
      # price registry does not carry is billed at a flat rate.
      def record_cost(amount, model:, tokens:, approximate: false)
        entry = nil
        @mutex.synchronize do
          @cost += amount
          @tokens_billed += tokens.to_i
          entry = { ts: Time.now.to_i, amount:, model:, tokens: tokens.to_i, total: @cost, billed: @tokens_billed }
          entry[:approximate] = true if approximate
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
        @mutex.synchronize { @conversations[current_key] = blank_conversation; @topic = nil }
        self
      end

      private

      # Always call inside @mutex. Created on read rather than up front, so a key
      # that has never spoken costs nothing.
      def current_key = Fiber[:master_conversation] || @active_key || LOCAL

      def conversation(key = nil) = @conversations[key || current_key] ||= blank_conversation

      def blank_conversation = { messages: [], token_est: 0, name: nil }

      def pruned_messages(key = nil)
        @mutex.synchronize do
          msgs = conversation(key || current_key)[:messages]
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
