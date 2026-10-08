# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ground/service_supervisor"

class TestBootNamespaces < Minitest::Test
  def test_service_supervisor_uses_the_absolute_io_namespace
    assert_includes Master::Ground::ServiceSupervisor.ancestors, Master::Io::AtomicWrite
  end

  def test_model_quota_loads_through_the_master_io_namespace
    require_relative "../lib/io/model_quota"
    assert defined?(Master::Io::ModelQuota)
    assert Master::Io::ModelQuota.respond_to?(:snapshot)
  end
end
