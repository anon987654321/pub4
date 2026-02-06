# frozen_string_literal: true

require "minitest/autorun"
require "sqlite3"

# Create minimal MASTER module for testing
module MASTER
  def self.root
    File.expand_path("..", __dir__)
  end
  
  module DB
    def self.connection
      @connection ||= begin
        db = SQLite3::Database.new(":memory:")
        db.results_as_hash = true
        db.execute("CREATE TABLE IF NOT EXISTS personas (id INTEGER PRIMARY KEY, name TEXT UNIQUE, role TEXT, instructions TEXT, weight REAL)")
        db
      end
    end
    
    def self.get_persona(name)
      connection.get_first_row("SELECT * FROM personas WHERE name = ?", [name])
    end
  end
  
  module LLM
    def self.select_model(text_length)
      { model: "test-model", tier: :fast }
    end
    
    def self.remaining
      5.0
    end
  end
end

require_relative "../lib/result"
require_relative "../lib/stages"

module MASTER
  class TestStages < Minitest::Test
    def setup
      # Clear personas table
      DB.connection.execute("DELETE FROM personas")
    end

    # Intake tests
    def test_intake_passes_text_through
      stage = Stages::Intake.new
      result = stage.call({ text: "hello world" })
      
      assert result.ok?
      assert_equal "hello world", result.value[:text]
    end

    def test_intake_loads_persona
      # Insert test persona
      DB.connection.execute(
        "INSERT INTO personas (name, role, instructions, weight) VALUES (?, ?, ?, ?)",
        ["test_persona", "tester", "Be helpful", 1.0]
      )
      
      stage = Stages::Intake.new
      result = stage.call({ text: "hello", persona: "test_persona" })
      
      assert result.ok?
      assert_equal "Be helpful", result.value[:persona_instructions]
    end

    def test_intake_handles_missing_persona
      stage = Stages::Intake.new
      result = stage.call({ text: "hello", persona: "nonexistent" })
      
      assert result.ok?
      assert_nil result.value[:persona_instructions]
    end

    # Guard tests
    def test_guard_blocks_rm_rf_root
      stage = Stages::Guard.new
      result = stage.call({ text: "rm -rf /" })
      
      assert result.err?
      assert_match(/Blocked/, result.error)
    end

    def test_guard_blocks_drop_table
      stage = Stages::Guard.new
      result = stage.call({ text: "DROP TABLE users;" })
      
      assert result.err?
      assert_match(/Blocked/, result.error)
    end

    def test_guard_blocks_format_drive
      stage = Stages::Guard.new
      result = stage.call({ text: "FORMAT C:" })
      
      assert result.err?
      assert_match(/Blocked/, result.error)
    end

    def test_guard_allows_safe_commands
      stage = Stages::Guard.new
      result = stage.call({ text: "ls -la" })
      
      assert result.ok?
    end

    def test_guard_allows_safe_sql
      stage = Stages::Guard.new
      result = stage.call({ text: "SELECT * FROM users WHERE id = 1" })
      
      assert result.ok?
    end

    # Route tests
    def test_route_selects_model
      stage = Stages::Route.new
      result = stage.call({ text: "hello" })
      
      assert result.ok?
      assert_equal "test-model", result.value[:model]
      assert_equal :fast, result.value[:tier]
      assert_equal 5.0, result.value[:budget_remaining]
    end

    def test_route_handles_long_text
      stage = Stages::Route.new
      result = stage.call({ text: "x" * 1500 })
      
      assert result.ok?
      refute_nil result.value[:model]
    end

    # Render tests
    def test_render_typesets_prose
      stage = Stages::Render.new
      result = stage.call({ response: 'Hello "world" -- this is...' })
      
      assert result.ok?
      rendered = result.value[:rendered]
      assert_includes rendered, "\u201C" # Opening curly quote
      assert_includes rendered, "\u201D" # Closing curly quote
      assert_includes rendered, "\u2014" # Em dash
      assert_includes rendered, "\u2026" # Ellipsis
    end

    def test_render_preserves_code_blocks
      stage = Stages::Render.new
      input_text = <<~TEXT
        Here is some "prose" with quotes.
        
        ```ruby
        puts "This should not be typeset"
        ```
        
        More "prose" here.
      TEXT
      
      result = stage.call({ response: input_text })
      
      assert result.ok?
      rendered = result.value[:rendered]
      
      # Code block should be preserved exactly
      assert_includes rendered, 'puts "This should not be typeset"'
      
      # Prose should be typeset
      assert_includes rendered, "\u201C" # Opening curly quote (from "prose")
    end

    def test_render_handles_empty_response
      stage = Stages::Render.new
      result = stage.call({ response: "" })
      
      assert result.ok?
      assert_equal "", result.value[:rendered]
    end

    def test_render_handles_no_response_key
      stage = Stages::Render.new
      result = stage.call({})
      
      assert result.ok?
      assert_equal "", result.value[:rendered]
    end

    def test_render_preserves_nested_code_blocks
      stage = Stages::Render.new
      input_text = <<~TEXT
        Some text with "quotes".
        
        ```markdown
        Here is a markdown example with "quotes" too.
        ```
        
        More text with "quotes".
      TEXT
      
      result = stage.call({ response: input_text })
      
      assert result.ok?
      rendered = result.value[:rendered]
      
      # Inside code block should NOT be typeset
      assert_includes rendered, 'Here is a markdown example with "quotes" too.'
    end
  end
end
