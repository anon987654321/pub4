# frozen_string_literal: true

require "test_helper"
require_relative "../lib/fix/repair_loop"

# A model repair must not be asked for a file no automated writer may change:
# it tests its candidate by writing it in place, and the protected-path watch
# then stops the whole run.
class TestRepairLoopProtected < Minitest::Test
  Rule = Struct.new(:id, :severity)

  class AskingLoop < Master::Fix::RepairLoop
    attr_reader :asked

    def fix_violation(_violation)
      @asked = @asked.to_i + 1
      :applied
    end
  end

  def loop_for(id = "ABC_SIZE")
    AskingLoop.new(law: Rule.new(id, :warning), agent: Object.new, scanner: Object.new, root: Master::ROOT)
  end

  def test_a_protected_file_is_skipped_before_the_model_is_asked
    repair = loop_for
    face = File.join(Master::ROOT, "lib", "cli", "face", "ascii.rb")
    capture_io { repair.send(:fix_batch, [{ file: face, law: "ABC_SIZE", message: "m", severity: :warning }]) }

    assert_nil repair.asked
    assert_equal({ skip_protected: 1 }, repair.instance_variable_get(:@batch_breakdown))
  end

  def test_an_ordinary_file_still_reaches_the_model
    repair = loop_for
    plain = File.join(Master::ROOT, "lib", "ground", "law_resolver.rb")
    capture_io { repair.send(:fix_batch, [{ file: plain, law: "ABC_SIZE", message: "m", severity: :warning }]) }

    assert_equal 1, repair.asked
  end
end
