# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../../MASTER/gates/lib/source/engine_boundaries"

# One engine naming another engine's constant. These plant two engines in a
# temporary tree and pass it as the gate's root.
class EngineBoundariesGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::EngineBoundariesGate

  # A braceless string-keyed hash arrives as keywords, so the planted files are
  # taken from either place.
  # No exemptions by default: the real EXEMPT names a file no planted tree
  # carries, and an unmatched row is itself a failure.
  def over(files = {}, exempt: {}, **planted)
    files = files.merge(planted)
    Dir.mktmpdir do |dir|
      plant(dir, "RAILS/brgen/engines/dating/lib/dating/engine.rb", "module Dating\n  class Engine\n    isolate_namespace Dating\n  end\nend\n")
      plant(dir, "RAILS/brgen/engines/takeaway/lib/takeaway/engine.rb", "module Takeaway\n  class Engine\n    isolate_namespace Takeaway\n  end\nend\n")
      files.each { |rel, body| plant(dir, "RAILS/brgen/engines/#{rel}", body) }
      GATE.run(root: dir, exempt:)
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
    result = over(
      { "dating/app/controllers/dating/home_controller.rb" => "Takeaway::Order.where(user_id: 1)\n",
        "dating/app/controllers/dating/other_controller.rb" => "Takeaway::Order.where(user_id: 1)\n" },
      exempt: { "dating" => { "app/controllers/dating/home_controller.rb" => %w[Takeaway] } }
    )

    assert_equal 1, result.failures.size, result.failures.join(", ")
    assert_match(/other_controller/, result.failures.first)
  end

  def test_an_exemption_whose_read_is_gone_fails
    result = over(
      { "dating/app/controllers/dating/home_controller.rb" => "Dating::Profile.first\n" },
      exempt: { "dating" => { "app/controllers/dating/home_controller.rb" => %w[Takeaway] } }
    )

    assert_equal 1, result.failures.size, result.failures.join(", ")
    assert_match(%r{EXEMPT dating/app/controllers/dating/home_controller.rb => Takeaway matches no reference}, result.failures.first)
  end

  def test_this_tree_crosses_only_where_exempt_says
    result = GATE.run

    assert result.ok?, result.failures.join("\n")
    assert_operator result.checks_ran, :>=, 6, "fewer engines than brgen mounts — check the glob, not the tree"
  end

  def test_no_engines_is_inconclusive_rather_than_clean
    result = Dir.mktmpdir { |dir| GATE.run(root: dir) }

    assert_equal :inconclusive, result.outcome
  end
end
