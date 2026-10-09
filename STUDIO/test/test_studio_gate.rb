# frozen_string_literal: true

require "minitest/autorun"
require_relative "../gate"

class TestStudioGate < Minitest::Test
  def test_declared_entrypoints_exist_and_are_guarded
    %w[dilla/dilla.rb postpro/postpro.rb replicate/replicate.rb photograph.rb].each do |entry|
      path = File.join(Studio::Gate::ROOT, entry)
      assert File.file?(path), "missing STUDIO/#{entry}"
      assert_match(/__FILE__\s*==\s*(\$PROGRAM_NAME|\$0)|(\$PROGRAM_NAME|\$0)\s*==\s*__FILE__/, File.read(path))
    end
  end

  def test_real_tree_passes_gate
    result = Studio::Gate.new.run
    assert_empty result.instance_variable_get(:@failures).to_a
  end
end
