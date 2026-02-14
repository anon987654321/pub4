# frozen_string_literal: true

require "json"
require "fileutils"
require "yaml"

module MASTER
  # Store - Persists axioms, council, costs, sessions to JSONL files
  module DB
    extend self

    @mutex = Monitor.new
    @cache = {}

    # Initialize database at given path
    # @param path [String, nil] Database directory path (defaults to var/db)
    # @return [void]
    def setup(path: nil)
      @root = path || File.join(Paths.var, "db")
      FileUtils.mkdir_p(@root)
      @cache.clear
      ensure_seeded
    end

    # Get database root directory
    # @return [String] Absolute path to database directory
    def root
      @root ||= begin
        r = File.join(Paths.var, "db")
        FileUtils.mkdir_p(r)
        r
      end
    end

    # Load YAML configuration files from data/ directory
    def load_yml(name)
      yml_path = File.join(File.dirname(__dir__), "data", "#{name}.yml")
      return {} unless File.exist?(yml_path)
      
      YAML.safe_load_file(yml_path) || {}
    rescue StandardError => e
      Logging.error("Failed to load #{name}.yml: #{e.message}")
      {}
    end

    def synchronize(&block)
      @mutex.synchronize(&block)
    end

    # Clear all cached data
    # @return [void]
    def clear_cache
      @cache.clear
    end

    # --- Axioms (cached) ---
    
    # Get all axioms (cached)
    # @return [Array<Hash>] Array of axiom records
    def axioms
      @cache[:axioms] ||= read_collection("axioms")
    end

    # Add new axiom to database
    # @param name [String] Axiom name
    # @param description [String] Axiom description
    # @param category [String, nil] Category classification
    # @param scope [String, nil] Scope of application
    # @return [Hash] Created axiom record
    def add_axiom(name:, description:, category: nil, scope: nil)
      record = {
        name: name,
        description: description,
        category: category,
        scope: scope,
        created_at: Time.now.utc.iso8601,
      }
      append("axioms", record.compact)
      @cache.delete(:axioms)
    end

    # --- Council (cached) ---
    
    # Get all council personas (cached)
    # @return [Array<Hash>] Array of persona records
    def council
      # Try loading from YAML first for new structure, fall back to JSONL for backward compatibility
      yml_data = load_yml("council")
      if yml_data && yml_data["council"]
        yml_data["council"]
      else
        @cache[:council] ||= read_collection("council")
      end
    end

    # Add new council persona
    # @param name [String] Persona name
    # @param role [String] Role description
    # @param style [String] Communication style
    # @param bias [String, nil] Decision bias
    # @return [Hash] Created persona record
    def add_persona(name:, role:, style:, bias: nil)
      record = {
        name: name,
        role: role,
        style: style,
        bias: bias,
        created_at: Time.now.utc.iso8601,
      }
      append("council", record.compact)
      @cache.delete(:council)
    end

    # --- Costs ---
    
    # Log LLM API cost
    # @param model [String] Model identifier
    # @param tokens_in [Integer] Input tokens
    # @param tokens_out [Integer] Output tokens
    # @param cost [Float] Cost in dollars
    # @return [Hash] Created cost record
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

    # Get total cost across all logged API calls
    # @return [Float] Total cost in dollars
    def total_cost
      costs = read_collection("costs")
      costs.sum { |c| c[:cost] || 0 }
    end

    # Get recent cost records
    # @param limit [Integer] Number of records to return
    # @return [Array<Hash>] Recent cost records
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

    def increment_failure!(model)
      circuits = read_collection("circuits")
      existing = circuits.find { |c| c[:model] == model }

      if existing
        existing[:failures] = (existing[:failures] || 0) + 1
        existing[:last_failure] = Time.now.utc.iso8601
        # Keep state as-is (don't open yet)
        write_collection("circuits", circuits)
      else
        record = {
          model: model,
          state: "closed",
          failures: 1,
          last_failure: Time.now.utc.iso8601,
        }
        append("circuits", record)
      end
    end

    # --- Sessions ---
    # WARNING: This DB.save_session is for learning feedback only.
    # For actual session storage, use Memory.save_session in session.rb
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
      # Path traversal protection
      safe_name = File.basename(collection.to_s)
      File.join(root, "#{safe_name}.jsonl")
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
      temp_path = "#{path}.tmp"
      
      synchronize do
        File.open(temp_path, "w") do |f|
          f.flock(File::LOCK_EX)
          data.each { |item| f.puts(JSON.generate(item)) }
        end
        File.rename(temp_path, path)
      end
    end

    def append(collection, record)
      path = file_path(collection)
      synchronize do
        File.open(path, "a") do |f|
          f.flock(File::LOCK_EX)
          f.puts(JSON.generate(record))
        end
      end
      record
    end

    def ensure_seeded
      synchronize do
        seed_axioms if axioms.empty?
        seed_council if council.empty?
      end
    end

    def seed_axioms
      return unless read_collection("axioms").empty?
      
      axioms_file = File.join(MASTER.root, "data", "axioms.yml")
      if File.exist?(axioms_file)
        axioms_data = YAML.safe_load_file(axioms_file, symbolize_names: true)
        axioms_data.each do |axiom|
          add_axiom(
            name: axiom[:id] || axiom[:name],
            description: axiom[:statement] || axiom[:description],
            category: axiom[:category] || "core"
          )
        end
      else
        # Fallback to hardcoded defaults
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
    end

    def seed_council
      return unless read_collection("council").empty?
      default_council = [
        { name: "Architect", role: "system_design", style: "formal", bias: "structure" },
        { name: "Skeptic", role: "devil_advocate", style: "critical", bias: "caution" },
        { name: "Pragmatist", role: "implementation", style: "direct", bias: "shipping" },
        { name: "Security", role: "security_review", style: "paranoid", bias: "safety" },
        { name: "User", role: "ux_advocate", style: "empathetic", bias: "usability" },
        { name: "Mentor", role: "code_review", style: "teaching", bias: "clarity" },
        { name: "Historian", role: "precedent_analysis", style: "scholarly", bias: "context" },
        { name: "Minimalist", role: "simplification", style: "terse", bias: "reduction" },
        { name: "Devil", role: "adversarial_testing", style: "provocative", bias: "breaking" },
        { name: "Diplomat", role: "conflict_resolution", style: "balanced", bias: "consensus" },
      ]
      default_council.each { |c| add_persona(**c) }
    end
  end
end
