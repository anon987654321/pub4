# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/scan/rule_dsl"

# Both rules were near-total noise under /fix: every sampled SIMULATION
# finding was a conditional ("this test would pass having measured nothing"),
# and LAW_OF_DEMETER read hostnames and file names in YAML as call chains.
# Opus declined to "repair" them, one model call at a time. These pin what
# each rule is for, the half that fires and the half that must not.
class TestDemeterAndSimulationScope < Minitest::Test
  RB = "/repo/lib/example.rb"

  def rule(id) = Master::Review::Scan::Rule.registry.find { |klass| klass.name.nil? && klass.new.id == id }.new
  def fires?(id, src, path: RB) = rule(id).check("#{src}\n", path:).any?

  def test_demeter_fires_on_navigation
    ["x = order.buyer.profile.address", "x = @order.buyer.profile.address",
     "order.buyer(1).profile.address", "plan = user.account.plan.limits.first"].each do |src|
      assert fires?("LAW_OF_DEMETER", src), src
    end
  end

  def test_demeter_spares_pipelines_globals_and_data
    ["names = files.uniq.sort.reject(&:empty?)", "text.each_line.with_index.map { |l, i| l }",
     "Rails.application.config.x.master_container", "document.body.classList.add('x')",
     %(url = "https://pubmed.ncbi.nlm.nih.gov/"), "if @refs.session.messages.any?", "x = a.b.c"].each do |src|
      refute fires?("LAW_OF_DEMETER", src), src
    end
    refute fires?("LAW_OF_DEMETER", "web/public/three.face.module.js:", path: "/repo/PATH_OWNERSHIP.yml")
  end

  def test_simulation_fires_on_promises_and_reported_futures
    [%(warn "the deploy will restart relayd"), %(msg = "we will ship it"),
     %(status("fix0", "this might break"))].each do |src|
      assert fires?("SIMULATION", src), src
    end
  end

  def test_simulation_spares_hypotheticals_and_past_failures
    [%(assert ok, "this test would pass having measured nothing"),
     %(warn "could not reach host"), %(puts "measured 3, which would have been a raise"),
     %(prompt = "what evidence would falsify your criticism?")].each do |src|
      refute fires?("SIMULATION", src), src
    end
    refute fires?("SIMULATION", "Five things that will bite you, in order:", path: "/repo/AGENTS.md")
  end
end
