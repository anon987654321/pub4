# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"

module Master
  class Session
    TOKENS_PER_CHAR  = 4
    SESSION_NAME_MAX = 40
    COSTS_MAX_BYTES  = 102_400     # 100 KB
    SESSION_DIR      = ".master"

    attr_reader :name, :messages, :cost, :phase, :snapshots

    def initialize(root: Dir.pwd, budget_max: 10.0, req_max: 1.0)
      @root       = Pathname.new(root)
      @budget_max = budget_max
      @req_max    = req_max
      @messages   = []
      @snapshots  = {}
      @cost       = 0.0
      @phase      = :discover
      @name       = nil
      @path       = @root.join(SESSION_DIR, "session.json")
      @costs_path = @root.join(SESSION_DIR, "costs.jsonl")
      ensure_session_dir
    end

    def add_message(role:, content:)
      msg = { role:, content:, ts: Time.now.to_i }
      @messages << msg
      @name ||= auto_name(content) if role == :user
      msg
    end

    def record_cost(amount, model:, tokens:)
      @cost += amount
      entry = { ts: Time.now.to_i, amount:, model:, tokens:, total: @cost }
      rotate_costs! if File.exist?(@costs_path) && File.size(@costs_path) > COSTS_MAX_BYTES
      File.open(@costs_path, "a") { |f| f.puts(JSON.generate(entry)) }
      entry
    end

    def snapshot(path, content)
      @snapshots[path] ||= []
      @snapshots[path] << content
    end

    def last_snapshot(path)
      @snapshots[path]&.last
    end

    def save!
      FileUtils.mkdir_p(@path.dirname)
      data = { name: @name, phase: @phase, messages: @messages, cost: @cost, ts: Time.now.to_i }
      File.write(@path, JSON.generate(data))
    end

    def load!
      return self unless File.exist?(@path)
      data = JSON.parse(File.read(@path), symbolize_names: true)
      @name     = data[:name]
      @phase    = data[:phase]&.to_sym || :discover
      @messages = data[:messages] || []
      @cost     = data[:cost].to_f
      self
    end

    def exists?    = File.exist?(@path)
    def clear!
      @messages = []
      @cost     = 0.0
      @name     = nil
      self
    end
    def token_est  = @messages.sum { |m| m[:content].to_s.bytesize / TOKENS_PER_CHAR }

    private

    def auto_name(content)
      content.to_s.split.first(5).join(" ").then { |s| s[0, SESSION_NAME_MAX] }
    end

    def rotate_costs!
      return unless File.exist?(@costs_path)

      lines = File.readlines(@costs_path)
      keep  = lines.last([lines.size / 2, 1].max)
      File.write(@costs_path, keep.join)
    end

    def ensure_session_dir
      FileUtils.mkdir_p(@root.join(SESSION_DIR)) unless Dir.exist?(@root.join(SESSION_DIR))
    end
  end
end