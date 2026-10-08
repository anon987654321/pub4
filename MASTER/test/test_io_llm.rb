# frozen_string_literal: true

require_relative "test_helper"

class IoLlmTest < Minitest::Test
  def test_llm_tool_forwarding_source_compiles
    path = File.expand_path("../lib/io/llm.rb", __dir__)
    source = File.read(path)
    assert_silent { RubyVM::InstructionSequence.compile(source, path) }
  end
end
