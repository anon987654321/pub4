# frozen_string_literal: true

require_relative "test_helper"

class TestIngressJobs < Minitest::Test
  def test_lookup_cron_self_test
    job = Master::Ground::IngressJobs.lookup_cron("self_test")
    assert job
    assert_equal "cron", job["kind"]
  end
end
