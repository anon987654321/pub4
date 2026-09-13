# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/engine_boundaries"

# One engine naming another engine's constant. The gate reads a ROOT fixed at
# load time, so these plant two engines in a temporary tree and rewrite ROOT
# around the call.
class EngineBoundariesGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::EngineBoundariesGate

  def over(files)
    Dir.mktmpdir do |dir|
      plant(dir, "RAILS/brgen/engines/dating/lib/dating/engine.rb", "module Dating\n  class Engine\n    isolate_namespace Dating\n  end\nend\n")
      plant(dir, "RAILS/brgen/engines/takeaway/lib/takeaway/engine.rb", "module Takeaway\n  class Engine\n    isolate_namespace Takeaway\n  end\nend\n")
      files.each { |rel, body| plant(dir, "RAILS/brgen/engines/#{rel}", body) }
      with_constants(GATE, ROOT: dir) { GATE.run }
    end
  end

  def test_an_engine_naming_another_engines_model_fails
    result = over("dating/app/models/dating/match.rb" => "class Dating::Match\n  def order = Takeaway::Order.first\nend\n")

    refute result.ok?, "a cross-engine constant passed"
    assert_match(%r{dating/app/models/dating/match.rb:2 names Takeaway::}, result.failures.first)
  end

  def test_a_class_name_string_counts_too
    result = over("dating/app/models/dating/match.rb" => %(has_many :orders, class_name: "Takeaway::Order"\n))

    refute result.ok?
  end

  def test_its_own_namespace_and_comments_pass
    result = over(
      "dating/app/models/dating/match.rb" => "# Same defect as Takeaway::Order#delivery_fee.\nclass Dating::Match < Dating::ApplicationRecord; end\n",
      "takeaway/app/views/takeaway/orders/show.html.erb" => "<%# see Dating::Match %>\n<%= ::Takeaway::Order.count %>\n"
    )

    assert result.ok?, result.failures.join(", ")
    assert_equal 2, result.checks_ran
  end

  def test_a_declared_read_passes_and_only_for_its_file
    with_constants(GATE, EXEMPT: { "dating" => { "app/controllers/dating/home_controller.rb" => %w[Takeaway] } }) do
      result = over(
        "dating/app/controllers/dating/home_controller.rb" => "Takeaway::Order.where(user_id: 1)\n",
        "dating/app/controllers/dating/other_controller.rb" => "Takeaway::Order.where(user_id: 1)\n"
      )

      assert_equal 1, result.failures.size, result.failures.join(", ")
      assert_match(/other_controller/, result.failures.first)
    end
  end

  def test_no_engines_is_inconclusive_rather_than_clean
    result = Dir.mktmpdir { |dir| with_constants(GATE, ROOT: dir) { GATE.run } }

    assert_equal :inconclusive, result.outcome
  end
end
