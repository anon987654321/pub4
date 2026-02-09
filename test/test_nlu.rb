# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/nlu'

class TestNLU < Minitest::Test
  def test_empty_input_returns_error
    result = MASTER::NLU.parse("")
    assert_equal :unknown, result[:intent]
    assert result[:error]
  end

  def test_nil_input_returns_error
    result = MASTER::NLU.parse(nil)
    assert_equal :unknown, result[:intent]
    assert result[:error]
  end

  def test_extract_files_with_extensions
    text = "refactor lib/user.rb and test/user_test.rb"
    files = MASTER::NLU.extract_files(text)
    
    assert_includes files, "lib/user.rb"
    assert_includes files, "test/user_test.rb"
  end

  def test_extract_files_with_quotes
    text = 'analyze "src/main.js" and check "config.yml"'
    files = MASTER::NLU.extract_files(text)
    
    assert_includes files, "src/main.js"
    assert_includes files, "config.yml"
  end

  def test_extract_files_various_extensions
    text = "check script.sh, config.yaml, and data.json"
    files = MASTER::NLU.extract_files(text)
    
    assert_includes files, "script.sh"
    assert_includes files, "config.yaml"
    assert_includes files, "data.json"
  end

  def test_extract_intent_keywords_refactor
    text = "refactor the authentication code"
    intents = MASTER::NLU.extract_intent_keywords(text)
    assert_includes intents, :refactor
  end

  def test_extract_intent_keywords_analyze
    text = "analyze the database connection logic"
    intents = MASTER::NLU.extract_intent_keywords(text)
    assert_includes intents, :analyze
  end

  def test_extract_intent_keywords_explain
    text = "explain how this function works"
    intents = MASTER::NLU.extract_intent_keywords(text)
    assert_includes intents, :explain
  end

  def test_extract_intent_keywords_fix
    text = "fix the bug in user authentication"
    intents = MASTER::NLU.extract_intent_keywords(text)
    assert_includes intents, :fix
  end

  def test_extract_intent_keywords_search
    text = "search for database queries"
    intents = MASTER::NLU.extract_intent_keywords(text)
    assert_includes intents, :search
  end

  def test_extract_intent_keywords_show
    text = "show me the user model"
    intents = MASTER::NLU.extract_intent_keywords(text)
    assert_includes intents, :show
  end

  def test_extract_intent_keywords_list
    text = "list all controllers"
    intents = MASTER::NLU.extract_intent_keywords(text)
    assert_includes intents, :list
  end

  def test_extract_intent_keywords_multiple
    text = "analyze and refactor the code"
    intents = MASTER::NLU.extract_intent_keywords(text)
    assert_includes intents, :analyze
    assert_includes intents, :refactor
  end

  def test_fallback_parse_with_refactor_keyword
    result = MASTER::NLU.send(:fallback_parse, "refactor lib/user.rb")
    
    assert_equal :refactor, result[:intent]
    assert_includes result[:entities][:files], "lib/user.rb"
    assert result[:confidence] > 0.5
    assert_equal :fallback, result[:method]
  end

  def test_fallback_parse_with_analyze_keyword
    result = MASTER::NLU.send(:fallback_parse, "analyze test/user_test.rb")
    
    assert_equal :analyze, result[:intent]
    assert_includes result[:entities][:files], "test/user_test.rb"
    assert result[:confidence] > 0.5
  end

  def test_fallback_parse_without_keywords
    result = MASTER::NLU.send(:fallback_parse, "do something with code")
    
    assert_equal :unknown, result[:intent]
    assert result[:confidence] < 0.5
    assert result[:clarification_needed]
  end

  def test_parse_llm_response_valid_json
    json_response = {
      intent: "refactor",
      entities: {
        files: ["lib/user.rb"],
        target: "authentication logic"
      },
      confidence: 0.95,
      clarification_needed: false
    }.to_json

    result = MASTER::NLU.send(:parse_llm_response, json_response, "refactor auth")
    
    assert_equal :refactor, result[:intent]
    assert_equal 0.95, result[:confidence]
    assert_equal :llm, result[:method]
  end

  def test_parse_llm_response_with_markdown_json
    markdown_response = <<~MARKDOWN
      ```json
      {
        "intent": "analyze",
        "entities": {
          "files": ["lib/main.rb"]
        },
        "confidence": 0.9
      }
      ```
    MARKDOWN

    result = MASTER::NLU.send(:parse_llm_response, markdown_response, "analyze main")
    
    assert_equal :analyze, result[:intent]
    assert_equal 0.9, result[:confidence]
  end

  def test_parse_llm_response_invalid_json
    invalid_response = "This is not JSON"
    
    result = MASTER::NLU.send(:parse_llm_response, invalid_response, "refactor user.rb")
    
    # Should fallback to text extraction
    assert result[:intent]
    assert_equal :text_extraction, result[:method]
    assert result[:error]
  end

  def test_normalize_intent_with_valid_data
    data = {
      intent: "refactor",
      entities: { files: ["test.rb"] },
      confidence: 0.8
    }

    result = MASTER::NLU.send(:normalize_intent, data)
    
    assert_equal :refactor, result[:intent]
    assert_equal 0.8, result[:confidence]
    assert_equal :llm, result[:method]
  end

  def test_normalize_intent_with_invalid_intent
    data = {
      intent: "invalid_intent",
      entities: {},
      confidence: 0.5
    }

    result = MASTER::NLU.send(:normalize_intent, data)
    
    # Should default to :unknown for invalid intents
    assert_equal :unknown, result[:intent]
  end

  def test_build_classification_prompt
    prompt = MASTER::NLU.send(:build_classification_prompt, "refactor user.rb", {})
    
    assert_includes prompt, "refactor user.rb"
    assert_includes prompt, "intent"
    assert_includes prompt, "entities"
    assert_includes prompt, "JSON"
  end

  def test_build_classification_prompt_with_context
    context = {
      previous_command: "analyze lib/",
      current_file: "lib/user.rb"
    }
    
    prompt = MASTER::NLU.send(:build_classification_prompt, "refactor it", context)
    
    assert_includes prompt, "Previous command: analyze lib/"
    assert_includes prompt, "Current context: lib/user.rb"
  end

  def test_intent_schema_structure
    schema = MASTER::NLU.send(:intent_schema)
    
    assert_equal "object", schema[:type]
    assert schema[:properties][:intent]
    assert schema[:properties][:entities]
    assert schema[:properties][:confidence]
    assert_includes schema[:required], "intent"
  end

  def test_error_result
    result = MASTER::NLU.send(:error_result, "Test error")
    
    assert_equal :unknown, result[:intent]
    assert_equal "Test error", result[:error]
    assert_equal 0.0, result[:confidence]
    assert_equal :error, result[:method]
  end

  def test_extract_intent_from_text
    text = "The intent is to refactor the code"
    intent = MASTER::NLU.send(:extract_intent_from_text, text)
    
    assert_equal :refactor, intent
  end

  def test_extract_intent_from_text_unknown
    text = "No recognizable intent here"
    intent = MASTER::NLU.send(:extract_intent_from_text, text)
    
    assert_equal :unknown, intent
  end
end
