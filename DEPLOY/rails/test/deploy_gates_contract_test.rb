# frozen_string_literal: true

require "minitest/autorun"

class DeployGatesContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DEPLOY_ROOT = File.expand_path("../..", __dir__)

  GATE_FILES = %w[
    schema_migration_gate.rb
    generated_asset_freshness_gate.rb
    human_walkthrough_gate.rb
    rails_runtime_gate.rb
  ].freeze

  def test_gate_scripts_exist
    GATE_FILES.each do |name|
      path = File.join(ROOT, name)
      assert File.file?(path), "missing #{name}"
      assert_match(/^(#!|# frozen_string_literal)/, File.read(path, 40), "#{name} should be a Ruby gate script")
    end
  end

  def test_check_rails_wires_new_gates
    source = File.read(File.join(DEPLOY_ROOT, "bin", "check-rails"))
    %w[schema_migration_gate generated_asset_freshness_gate rails_runtime_gate].each do |gate|
      assert_includes source, gate
    end
  end

  def test_integrity_gate_wires_new_gates
    source = File.read(File.join(DEPLOY_ROOT, "integrity_gate.rb"))
    %w[schema_migration asset_freshness human_walkthrough].each do |gate|
      assert_includes source, gate
    end
  end

  def test_bsdports_queue_schema_present
    assert File.file?(File.join(ROOT, "bsdports/db/queue_schema.rb"))
  end

  def test_hjerterom_operator_dashboard_route
    routes = File.read(File.join(ROOT, "hjerterom/config/routes.rb"))
    assert_includes routes, 'get "operator", to: "operator#index"'
  end
end