# frozen_string_literal: true

require_relative "test_helper"
require "operator/word_rename"

# The gate -> check rename of 2026-10-22, in miniature: every spelling of the word renamed in text and path,
# the words that only contain it left alone, and a kept second meaning left alone. laws.yml is ordinary
# versioned source since configuration lost its path immutability, so it renames with the rest.
class TestWordRename < Minitest::Test
  SOURCE = <<~RUBY
    class GateChain
      GATES = %w[lexical].freeze
      def run_gate = aggregate(gateway)
      def weave = gate_weave
      def line?(text) = text.match?(/\\Agates\\d+ at/)
    end
  RUBY

  def test_every_spelling_moves_and_nothing_else_does
    in_repo do |root|
      renamer = Operator::WordRename.new("gate", "check", root:, keep: ["gate_weave"])
      renamer.apply!(renamer.changes)

      expected = SOURCE.gsub("GateChain", "CheckChain").gsub("GATES", "CHECKS").gsub("run_gate", "run_check")
      assert_equal expected.gsub('\Agates', '\Achecks'),
                   File.read(File.join(root, "lib/check_chain.rb"))
      refute File.exist?(File.join(root, "lib/gate_chain.rb"))
      assert_equal "checks: lexical\n", File.read(File.join(root, "MASTER/data/laws.yml"))
    end
  end

  def test_a_move_onto_a_taken_path_is_a_collision
    in_repo do |root|
      File.write(File.join(root, "lib/check_chain.rb"), "taken\n")
      system("git", "-C", root, "add", "-A", out: File::NULL)
      renamer = Operator::WordRename.new("gate", "check", root:)

      assert_equal ["lib/gate_chain.rb"], renamer.collisions(renamer.changes).map(&:from)
    end
  end

  def in_repo
    Dir.mktmpdir do |root|
      { "lib/gate_chain.rb" => SOURCE, "MASTER/data/laws.yml" => "gates: lexical\n" }.each do |path, text|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), text)
      end
      system("git", "-C", root, "init", "-q") && system("git", "-C", root, "add", "-A")
      yield root
    end
  end
end
