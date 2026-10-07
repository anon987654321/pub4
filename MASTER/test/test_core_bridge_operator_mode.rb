# frozen_string_literal: true

require "test_helper"
require "cli/core_bridge"
require "tmpdir"

class CoreBridgeOperatorModeTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:, **) = @effects.shift
  end

  def test_observe_mode_completes_after_read_without_mutation_authority
    Dir.mktmpdir do |root|
      File.write(File.join(root, "README.md"), "hello\n")
      model = ScriptedModel.new(
        Master::Core::Effect.read("README.md"),
        Master::Core::Effect.done("read-only assessment"),
      )
      result = Master::CLI::CoreBridge.run(
        "inspect the repository", root:, model:, mode: :observe, max_turns: 2
      )
      assert_equal :complete, result[:reason]
      assert_equal "observe", result[:mission].dig("operator", "mode")
    end
  end
end
