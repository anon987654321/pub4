# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestSubdomainOrchestrator < Minitest::Test
  def setup
    @tool = Master::Io::SubdomainOrchestrator.new
  end

  def test_detect_intent
    assert_equal "maps", Master::Io::SubdomainOrchestrator.detect_intent("check maps viewport")
    assert_equal "bsdports", Master::Io::SubdomainOrchestrator.detect_intent("sync bsdports index")
    assert_nil Master::Io::SubdomainOrchestrator.detect_intent("hello world")
  end

  def test_brgen_cluster_payload
    result = @tool.call(domain: "playlist", context: "sync tracks")
    assert_predicate result, :ok?
    payload = result.value!
    assert_equal "rails-multi-tenant", payload[:cluster]
    assert_equal "playlist", payload[:subdomain]
  end

  def test_unknown_domain
    result = @tool.call(domain: "nope")
    refute result.ok?
  end
end
