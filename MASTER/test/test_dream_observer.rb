# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/dream_observer"

class TestDreamObserver < Minitest::Test
  def test_observe_ranks_evidence_and_writes_only_queue
    Dir.mktmpdir do |dir|
      Master::Operator::DreamObserver.stub(:add_todo, ->(items, _) {
        items << { kind: "todo", priority: 40, source: "TODO.md:1", text: "inspect" }
      }) do
        Master::Operator::DreamObserver.stub(:add_sprawl, ->(items, _) {
          items << { kind: "structure", priority: 10, source: "sprawl", text: "flatten" }
        }) do
          Master::Operator::DreamObserver.stub(:add_duplicates, ->(items, _) {}) do
            Master::Operator::DreamObserver.stub(:add_dirty, ->(items, _) {}) do
              rows = Master::Operator::DreamObserver.observe(root: dir)
              assert_equal "structure", rows.first[:kind]
              assert File.file?(File.join(dir, ".master", "dream_queue.yml"))
              refute File.file?(File.join(dir, "TODO.md"))
            end
          end
        end
      end
    end
  end
end
