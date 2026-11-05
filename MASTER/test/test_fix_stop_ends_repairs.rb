# frozen_string_literal: true

require_relative "test_helper"

# The stall guard says "STOPPING ... ending the repair to prove what it did", but the stop was read
# only at pass boundaries: a run kept attempting files for 40 minutes after it. Once the run is
# stopping, no further file goes to the model.
class TestFixStopEndsRepairs < Minitest::Test
  Rule = Struct.new(:id, :severity)

  class CountingAgent
    attr_reader :asked

    def initialize = @asked = 0

    def ask(_prompt)
      @asked += 1
      "```ruby\nclean\n```"
    end

    def ask_once(_prompt, **) = "SAFE"
  end

  def violation(path)
    Master::Fix::Violation.from_finding({ law: "TEST_RULE", severity: :warning, line: 1, message: "fix me" },
                                        file: path, ext: ".rb")
  end

  def files_in(root)
    %w[one.rb two.rb].map { |name| File.join(root, name).tap { |path| File.write(path, "violation\n") } }
  end

  def test_a_stopping_run_attempts_no_further_file
    Dir.mktmpdir do |root|
      paths = files_in(root)
      agent = CountingAgent.new
      loop = Master::Fix::RepairLoop.new(law: Rule.new("TEST_RULE", :warning), agent:, scanner: nil, root:)

      fixed = Master::Fix::RunBudget.stub(:stopping, "stalled, no yield") do
        loop.send(:fix_batch, paths.map { |path| violation(path) })
      end

      assert_equal 0, fixed
      assert_equal 0, agent.asked
      assert_equal(["violation\n"] * 2, paths.map { |path| File.read(path) })
    end
  end
end
