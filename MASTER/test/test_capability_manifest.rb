# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/capability_manifest"

class TestCapabilityManifest < Minitest::Test
  def test_unexercised_capabilities_are_not_reported_as_available
    manifest = Operator::CapabilityManifest.new(root: Master::ROOT).call
    capabilities = manifest.fetch("capabilities")
    %w[local_shell remote_shell browser github_api test_execution].each do |name|
      assert_equal "not_probed", capabilities.fetch(name).fetch("status")
    end
  end

  def test_running_ruby_is_grounded_in_the_current_process
    manifest = Operator::CapabilityManifest.new(root: Master::REPO_ROOT).call
    assert_equal "available", manifest.dig("capabilities", "ruby_runtime", "status")
    assert_includes manifest.dig("capabilities", "ruby_runtime", "evidence"), RUBY_VERSION
  end

  def test_write_permission_is_not_mislabelled_as_a_completed_write
    manifest = Operator::CapabilityManifest.new(root: Master::REPO_ROOT).call
    status = manifest.dig("capabilities", "repository_write_permission", "status")
    assert_includes %w[permission_observed permission_denied], status
  end
end
