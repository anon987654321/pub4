# frozen_string_literal: true

require "minitest/autorun"
require "sqlite3"
require "yaml"
require "tempfile"

# Create a minimal MASTER module for testing
module MASTER
  def self.root
    File.expand_path("..", __dir__)
  end
end

require_relative "../lib/db"

module MASTER
  class TestDB < Minitest::Test
    def setup
      # Use in-memory database for tests
      @original_connection = DB.instance_variable_get(:@connection)
      DB.instance_variable_set(:@connection, nil)
      
      @db = SQLite3::Database.new(":memory:")
      @db.results_as_hash = true
      DB.instance_variable_set(:@connection, @db)
      
      DB.schema
    end

    def teardown
      DB.instance_variable_set(:@connection, @original_connection)
    end

    def test_schema_creates_tables
      tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
      table_names = tables.map { |row| row["name"] }
      
      assert_includes table_names, "principles"
      assert_includes table_names, "personas"
      assert_includes table_names, "config"
      assert_includes table_names, "costs"
      assert_includes table_names, "circuits"
    end

    def test_schema_is_idempotent
      # Run schema twice - should not error
      DB.schema
      DB.schema
      
      tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table'")
      assert_equal 5, tables.count
    end

    def test_get_config_returns_value
      DB.set_config("test_key", "test_value")
      assert_equal "test_value", DB.get_config("test_key")
    end

    def test_get_config_returns_nil_for_missing
      assert_nil DB.get_config("nonexistent")
    end

    def test_set_config_updates_existing
      DB.set_config("key", "value1")
      DB.set_config("key", "value2")
      assert_equal "value2", DB.get_config("key")
    end

    def test_get_persona_returns_row
      @db.execute(
        "INSERT INTO personas (name, role, instructions, weight) VALUES (?, ?, ?, ?)",
        ["test_persona", "tester", "Be helpful", 1.0]
      )
      
      persona = DB.get_persona("test_persona")
      refute_nil persona
      assert_equal "test_persona", persona["name"]
      assert_equal "tester", persona["role"]
    end

    def test_get_persona_returns_nil_for_missing
      assert_nil DB.get_persona("nonexistent")
    end

    def test_seed_file_with_principles
      # Create temporary YAML file
      Tempfile.create(["principles", ".yml"]) do |f|
        f.write(YAML.dump({
          "principles" => {
            "test-principle" => {
              "name" => "Test Principle",
              "description" => "A test principle",
              "tier" => "core"
            }
          }
        }))
        f.flush
        
        DB.seed_file("principles", f.path)
        
        row = @db.get_first_row("SELECT * FROM principles WHERE name = ?", ["Test Principle"])
        refute_nil row
        assert_equal "Test Principle", row["name"]
        assert_equal "A test principle", row["text"]
        assert_equal "PROTECTED", row["protection_level"]
      end
    end

    def test_seed_file_with_personas
      # Create temporary YAML file
      Tempfile.create(["personas", ".yml"]) do |f|
        f.write(YAML.dump({
          "personas" => {
            "tester" => {
              "name" => "Tester",
              "description" => "Test persona",
              "system_prompt" => "You are a tester"
            }
          }
        }))
        f.flush
        
        DB.seed_file("personas", f.path)
        
        row = @db.get_first_row("SELECT * FROM personas WHERE name = ?", ["Tester"])
        refute_nil row
        assert_equal "Tester", row["name"]
        assert_equal "You are a tester", row["instructions"]
      end
    end
  end
end
