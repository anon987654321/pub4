# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/transformation_plan"
require_relative "../lib/fix/research_pass"

class TestResearchPass < Minitest::Test
  class ResearchAgent
    attr_reader :calls

    def initialize(records)
      @records = records
      @calls = nil
    end

    def research_sources(**arguments, &progress)
      @calls = arguments
      @records.each_with_index do |record, index|
        progress&.call(
          event: "completed", kind: record.fetch("kind"), index: index + 1,
          total: @records.size, label: record.fetch("label"), status: record.fetch("status")
        )
      end
      @records
    end
  end

  class TraceBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(name, **payload)
      @events << [name, payload]
    end
  end

  def setup
    @plan = Master::Fix::TransformationPlan.new(root: Master::ROOT)
  end

  def test_music_target_uses_arxiv_github_and_musictheory_research_context
    agent = ResearchAgent.new([
      { "kind" => "fetch", "label" => "https://arxiv.org/abs/1904.03442", "status" => "ok", "text" => "Microtiming evidence." },
      { "kind" => "fetch", "label" => "https://github.com/JakebGutierrez/wobblemidi", "status" => "ok", "text" => "Correlated drum-clock implementation." },
    ])
    bus = TraceBus.new
    pass = Master::Fix::ResearchPass.new(agent:, bus:, plan: @plan, root: Master::REPO_ROOT)

    result = pass.run(target: "STUDIO/dilla", files: %w[a.rb b.rb])

    assert_equal "PASS", result.fetch(:status)
    assert_equal "music", result.fetch(:domain)
    assert_includes agent.calls.fetch(:queries).join(" "), "musictheory"
    assert_includes agent.calls.fetch(:sources).join(" "), "arxiv.org/html/1904.03442v1"
    assert_includes agent.calls.fetch(:sources).join(" "), "github.com"
    assert_includes result.fetch(:brief), "untrusted evidence"
    assert_includes result.fetch(:brief), "Microtiming evidence."
    assert_includes result.fetch(:brief), "eligible files: 2"
    assert bus.events.any? { |name, _| name == "fix_loop:research" }
  end

  def test_research_below_independent_source_threshold_is_inconclusive
    agent = ResearchAgent.new([
      { "kind" => "fetch", "label" => "https://github.com/rails/rails", "status" => "ok", "text" => "Rails code." },
    ])
    pass = Master::Fix::ResearchPass.new(agent:, bus: nil, plan: @plan, root: Master::REPO_ROOT)

    result = pass.run(target: "RAILS", files: [])

    assert_equal "INCONCLUSIVE", result.fetch(:status)
    assert_includes result.fetch(:brief), "INCONCLUSIVE"
    assert_includes result.fetch(:brief), "higher uncertainty"
  end

  def test_agent_without_research_capability_does_not_claim_a_pass
    pass = Master::Fix::ResearchPass.new(agent: Object.new, bus: nil, plan: @plan, root: Master::REPO_ROOT)

    result = pass.run(target: "MASTER", files: [])

    assert_equal "INCONCLUSIVE", result.fetch(:status)
    assert_equal 0, result.fetch(:fetched_count)
  end

  def test_inconclusive_brief_names_failed_and_empty_source_fetches
    agent = ResearchAgent.new([
      { "kind" => "fetch", "label" => "https://github.com/rails/rails",
        "status" => "unavailable", "text" => "web_fetch: timed out" },
      { "kind" => "fetch", "label" => "https://guides.rubyonrails.org/",
        "status" => "empty", "text" => "" },
    ])
    pass = Master::Fix::ResearchPass.new(agent:, bus: nil, plan: @plan, root: Master::REPO_ROOT)

    result = pass.run(target: "RAILS", files: [])

    assert_equal "INCONCLUSIVE", result.fetch(:status)
    assert_includes result.fetch(:brief), "SOURCE [rails] UNAVAILABLE: https://github.com/rails/rails"
    assert_includes result.fetch(:brief), "web_fetch: timed out"
    assert_includes result.fetch(:brief), "SOURCE [rails] EMPTY: https://guides.rubyonrails.org/"
    assert_includes result.fetch(:brief), "(no text returned)"
  end

  def test_research_exception_returns_readable_multiline_inconclusive_brief
    agent = Object.new
    def agent.research_sources(**)
      raise IOError, "network unavailable"
    end
    pass = Master::Fix::ResearchPass.new(agent:, bus: nil, plan: @plan, root: Master::REPO_ROOT)

    result = pass.run(target: "RAILS", files: [])

    assert_equal "INCONCLUSIVE", result.fetch(:status)
    assert_includes result.fetch(:brief),
      "EXTERNAL RESEARCH PREFLIGHT: INCONCLUSIVE\nResearch could not be completed: IOError: network unavailable\nUse local laws"
    refute_includes result.fetch(:brief), "\\nResearch could not"
  end

  class WideResearchAgent
    def research_sources(queries:, sources:, **)
      searches = Array(queries).map do |query|
        { "kind" => "search", "label" => query, "status" => "ok",
          "text" => ("search evidence #{query} " * 50) }
      end
      pages = Array(sources).map do |url|
        { "kind" => "fetch", "label" => url, "status" => "ok",
          "text" => ("page evidence for #{url} " * 80) }
      end
      searches + pages
    end
  end

  def test_full_repository_brief_preserves_evidence_from_late_domains
    pass = Master::Fix::ResearchPass.new(
      agent: WideResearchAgent.new, bus: nil, plan: @plan, root: Master::REPO_ROOT,
    )

    result = pass.run(target: ".", files: %w[MASTER RAILS OPENBSD STUDIO])

    assert_equal "PASS", result.fetch(:status)
    %w[engineering rails openbsd studio music visual].each do |domain|
      assert_includes result.fetch(:brief), "Coverage #{domain}:"
      assert_includes result.fetch(:brief), "SOURCE [#{domain}]:"
    end
    assert_operator result.fetch(:brief).length, :<=, 8_000
    assert_includes result.fetch(:brief), "page evidence for https://github.com/dcyoung/r3f-audio-visualizer"
  end

  def test_full_repository_target_researches_every_domain
    pass = Master::Fix::ResearchPass.new(agent: Object.new, bus: nil, plan: @plan, root: Master::REPO_ROOT)

    assert_equal %w[engineering rails openbsd studio music visual].sort,
      pass.send(:domains_for, ".", @plan.research_protocol).sort
    assert_equal %w[engineering rails openbsd studio music visual].sort,
      pass.send(:domains_for, "MASTER RAILS OPENBSD STUDIO", @plan.research_protocol).sort
    assert_equal ["music"], pass.send(:domains_for, "STUDIO/dilla", @plan.research_protocol)
  end

  def test_domain_routing_does_not_confuse_full_repo_with_one_subtree
    pass = Master::Fix::ResearchPass.new(agent: Object.new, bus: nil, plan: @plan, root: Master::REPO_ROOT)

    assert_equal "music", pass.send(:domain_for, "/checkout/STUDIO/dilla")
    assert_equal "visual", pass.send(:domain_for, "STUDIO/postpro")
    assert_equal "rails", pass.send(:domain_for, "/checkout/RAILS")
    assert_equal "openbsd", pass.send(:domain_for, "OPENBSD")
    assert_equal "engineering", pass.send(:domain_for, "/checkout/pub4")
  end
end
