# frozen_string_literal: true

require "test_helper"
require_relative "../../kernel/master"

class NoSecretNoteTest < Minitest::Test
  def test_blocks_secrets_in_note_text
    data_dir = File.expand_path("../../data", __dir__)
    constitution = Master::Kernel::Constitution.load(data_dir:)
    memory = Master::Kernel::Memory.new
    effect = Master::Kernel::Effect.note(:debug, "token sk-#{'A' * 24}")

    verdict = constitution.admit(effect, memory)

    assert_instance_of Master::Kernel::Verdict::Block, verdict
    assert_equal :no_secret, verdict.by
  end
end