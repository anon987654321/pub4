# frozen_string_literal: true

require "json"
require "fileutils"

module MASTER
  # Store - Persists axioms, council, costs, sessions to JSONL files
  module DB
    extend self

    @mutex = Mutex.new

    def setup(path: nil)
      @root = path || File.join(Paths.var, "db")
      FileUtils.mkdir_p(@root)
      ensure_seeded
    end

    def root
      @root ||= begin
        r = File.join(Paths.var, "db")
        FileUtils.mkdir_p(r)
        r
      end
    end

    def synchronize(&block)
      @mutex.synchronize(&block)
    end

    # --- Axioms ---
    def axioms
      read_collection("axioms")
    end

    def add_axiom(name:, description:, category: nil, scope: nil)
      record = {
        name: name,
        description: description,
        category: category,
        scope: scope,
        created_at: Time.now.utc.iso8601,
      }
      append("axioms", record.compact)
    end

    # --- Council ---
    def council
      read_collection("council")
    end

    def add_persona(name:, role:, style:, bias: nil)
      record = {
        name: name,
        role: role,
        style: style,
        bias: bias,
        created_at: Time.now.utc.iso8601,
      }
      append("council", record.compact)
    end

    # --- Costs ---
    def log_cost(model:, tokens_in:, tokens_out:, cost:)
      record = {
        model: model,
        tokens_in: tokens_in,
        tokens_out: tokens_out,
        cost: cost,
        created_at: Time.now.utc.iso8601,
      }
      append("costs", record)
    end

    def total_cost
      costs = read_collection("costs")
      costs.sum { |c| c["cost"] || c[:cost] || 0 }
    end

    def recent_costs(limit: 10)
      read_collection("costs").last(limit)
    end

    # --- Circuits ---
    def circuit(model)
      circuits = read_collection("circuits")
      circuits.find { |c| c[:model] == model }
    end

    def trip!(model)
      circuits = read_collection("circuits")
      existing = circuits.find { |c| c[:model] == model }

      if existing
        existing[:state] = "open"
        existing[:failures] = (existing[:failures] || 0) + 1
        existing[:last_failure] = Time.now.utc.iso8601
        write_collection("circuits", circuits)
      else
        record = {
          model: model,
          state: "open",
          failures: 1,
          last_failure: Time.now.utc.iso8601,
        }
        append("circuits", record)
      end
    end

    def reset!(model)
      circuits = read_collection("circuits")
      existing = circuits.find { |c| c[:model] == model }

      return unless existing

      existing[:state] = "closed"
      existing[:failures] = 0
      write_collection("circuits", circuits)
    end

    # --- Sessions ---
    def save_session(id:, data:)
      sessions = read_collection("sessions")
      existing = sessions.find { |s| s[:id] == id }
      now = Time.now.utc.iso8601

      if existing
        existing[:data] = data
        existing[:updated_at] = now
        write_collection("sessions", sessions)
      else
        record = { id: id, data: data, created_at: now, updated_at: now }
        append("sessions", record)
      end
    end

    def load_session(id)
      sessions = read_collection("sessions")
      session = sessions.find { |s| s[:id] == id }
      session&.dig(:data)
    end

    # --- Patterns ---
    def patterns(category = nil)
      all = read_collection("patterns")
      return all unless category

      all.select { |p| p[:category] == category }
    end

    def add_pattern(category:, pattern:, replacement: nil, description: nil)
      record = {
        category: category,
        pattern: pattern,
        replacement: replacement,
        description: description,
      }
      append("patterns", record.compact)
    end

    # --- Models ---
    def models
      read_collection("models")
    end

    def add_model(name:, tier:, rate_in:, rate_out:)
      record = { name: name, tier: tier, rate_in: rate_in, rate_out: rate_out }
      append("models", record)
    end

    private

    def file_path(collection)
      File.join(root, "#{collection}.jsonl")
    end

    def read_collection(name)
      path = file_path(name)
      return [] unless File.exist?(path)

      synchronize do
        File.readlines(path).filter_map do |line|
          JSON.parse(line.strip, symbolize_names: true)
        rescue JSON::ParserError
          nil
        end
      end
    end

    def write_collection(name, data)
      path = file_path(name)
      synchronize do
        File.open(path, "w") do |f|
          data.each { |item| f.puts(JSON.generate(item)) }
        end
      end
    end

    def append(collection, record)
      path = file_path(collection)
      synchronize do
        File.open(path, "a") { |f| f.puts(JSON.generate(record)) }
      end
      record
    end

    def ensure_seeded
      seed_axioms if axioms.empty?
      seed_council if council.empty?
    end

    def seed_axioms
      default_axioms = [
        { name: "SRP", description: "Single Responsibility Principle", category: "solid" },
        { name: "OCP", description: "Open/Closed - open for extension, closed for modification", category: "solid" },
        { name: "DRY", description: "Don't Repeat Yourself", category: "core" },
        { name: "KISS", description: "Keep It Simple - reduce complexity, preserve UI/UX", category: "core", scope: "internal_logic" },
        { name: "small_files", description: "Files under 300 lines", category: "style" },
        { name: "NN/g", description: "Follow Nielsen Norman Group usability heuristics", category: "ux" },
      ]
      default_axioms.each { |a| add_axiom(**a) }
    end

    def seed_council
      default_council = [
        { name: "Architect", role: "system_design", style: "formal", bias: "structure" },
        { name: "Skeptic", role: "devil_advocate", style: "critical", bias: "caution" },
        { name: "Pragmatist", role: "implementation", style: "direct", bias: "shipping" },
        { name: "Security", role: "security_review", style: "paranoid", bias: "safety" },
        { name: "User", role: "ux_advocate", style: "empathetic", bias: "usability" },
        { name: "Mentor", role: "code_review", style: "teaching", bias: "clarity" },
      ]
      default_council.each { |c| add_persona(**c) }
    end
  end
end
