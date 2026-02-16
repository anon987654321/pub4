# frozen_string_literal: true

require "json"
require "fileutils"
require "yaml"

require_relative "db_jsonl/tables"

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
      # Cache the result regardless of source
      @cache[:council] ||= begin
        # Try loading from YAML first for new structure, fall back to JSONL for backward compatibility
        yml_data = load_yml("council")
        if yml_data && yml_data["council"]
          yml_data["council"]
        else
          read_collection("council")
        end
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
      unless File.exist?(axioms_file)
        Logging.error("CRITICAL: axioms.yml not found at #{axioms_file}")
        raise "axioms.yml not found - cannot initialize MASTER2"
      end

      axioms_data = YAML.safe_load_file(axioms_file, symbolize_names: true)
      axioms_data.each do |axiom|
        add_axiom(
          name: axiom[:id] || axiom[:name],
          description: axiom[:statement] || axiom[:description],
          category: axiom[:category] || "core"
        )
      end
    end

    def seed_council
      return unless read_collection("council").empty?

      council_file = File.join(MASTER.root, "data", "council.yml")
      unless File.exist?(council_file)
        Logging.error("CRITICAL: council.yml not found at #{council_file}")
        raise "council.yml not found - cannot initialize MASTER2"
      end

      council_data = YAML.safe_load_file(council_file, symbolize_names: true)
      council_data[:council]&.each do |member|
        add_persona(
          name: member[:name],
          role: member[:slug],
          style: "weight: #{member[:weight]}, temp: #{member[:temperature]}",
          bias: member[:veto] ? "veto" : "advisory"
        )
      end
    end
  end
end
