# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "session/persistence"
require_relative "session/snapshots"

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

      attr_reader :name, :messages, :cost, :phase, :snapshots, :budget_max
      attr_accessor :topic, :last_inferred_command, :last_inferred_args

      def initialize(root: Dir.pwd, budget_max: 10.0, req_max: 1.0)
        @root = root
        @budget_max = budget_max
        @req_max = req_max
        @mutex = Mutex.new
        @messages = []
        @token_est = 0
        @snapshots = {}
        @cost = 0.0
        @phase = :discover
        @name = nil
        @topic = nil
        @last_inferred_command = nil
        @last_inferred_args = nil
        @path = File.join(root, ".master", "session.json")
        @costs_path = File.join(root, ".master", "costs.jsonl")
        Dir.mkdir(File.join(root, ".master")) unless Dir.exist?(File.join(root, ".master"))
      end

      def add_message(role:, content:)
        msg = { role:, content:, ts: Time.now.to_i }
        @mutex.synchronize do
          @messages << msg
          @token_est += Session.estimate_tokens(content)
          @name ||= auto_name(content) if role == :user
        end
        msg
      end

      def record_cost(amount, model:, tokens:)
        entry = nil
        @mutex.synchronize do
          @cost += amount
          entry = { ts: Time.now.to_i, amount:, model:, tokens:, total: @cost }
        end
        rotate_costs! if File.exist?(@costs_path) && File.size(@costs_path) > COSTS_MAX_BYTES
        File.open(@costs_path, "a") { |f| f.puts(JSON.generate(entry)) }
        entry
      end

      def self.estimate_tokens(text) = text.to_s.bytesize / TOKENS_PER_CHAR

      def exists? = File.exist?(@path)
      def clear!
        @mutex.synchronize { @messages = []; @token_est = 0; @cost = 0.0; @name = nil; @topic = nil }
        self
      end

      def token_est
        @mutex.synchronize { @token_est }
      end

      private

      def pruned_messages
        @mutex.synchronize do
          return @messages if @messages.size <= FULL_MESSAGE_WINDOW

          older = @messages[0...-FULL_MESSAGE_WINDOW]
          recent = @messages.last(FULL_MESSAGE_WINDOW)
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
