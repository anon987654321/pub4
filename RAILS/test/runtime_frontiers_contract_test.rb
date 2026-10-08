# frozen_string_literal: true

require "minitest/autorun"

class RuntimeFrontiersContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze

  def read(app, relative)
    File.read(File.join(ROOT, app, relative))
  end

  def test_solid_cable_is_production_transport_with_a_dedicated_database
    APPS.each do |app|
      cable = read(app, "config/cable.yml")
      database = read(app, "config/database.yml")
      schema = read(app, "db/cable_schema.rb")

      assert_match(/production:\n(?:.*\n){0,12}\s*adapter:\s*solid_cable/, cable, "#{app}: production cable adapter is not Solid Cable")
      assert_includes cable, "writing: cable", "#{app}: Solid Cable does not use its cable database"
      assert_includes cable, "CABLE_POLLING_INTERVAL", "#{app}: cable latency is not operationally tunable"
      assert_match(/^  production:\n[\s\S]*?^  cable:\n/m, database, "#{app}: production has no dedicated cable database")
      assert_includes database, "migrations_paths: db/cable_migrate"
      assert_includes schema, 'create_table "solid_cable_messages"'
      assert_includes schema, 't.binary "payload", limit: 536870912, null: false'
    end
  end

  def test_cable_polling_is_not_hardwired_to_a_single_latency
    APPS.each do |app|
      cable = read(app, "config/cable.yml")
      assert_match(/CABLE_POLLING_INTERVAL/, cable)
      assert_match(/to_f\.seconds/, cable)
    end
  end

  def test_ractor_shareability_is_strict_during_tests
    APPS.each do |app|
      source = read(app, "config/environments/test.rb")
      assert_includes source, "ActiveSupport::Ractors.unshareable_proc_action = :raise",
                      "#{app}: test environment does not fail loudly on unshareable Rails state"
    end
  end

  def test_nested_runtime_data_can_be_made_shareable_without_mutating_the_source
    skip "Ruby Ractor shareability API unavailable" unless defined?(Ractor) &&
      Ractor.respond_to?(:make_shareable) && Ractor.respond_to?(:shareable?)

    source = { "labels" => ["brgen", "amber"], "limits" => { "tap" => 44 } }
    shared = Ractor.make_shareable(source, copy: true)

    refute Ractor.shareable?(source)
    assert Ractor.shareable?(shared)
    assert Ractor.shareable?(shared.fetch("labels"))
    assert_equal ["brgen", "amber"], source.fetch("labels")
  end

  def test_native_app_inventory_is_explicit_before_any_bridge_is_added
    source = File.read(File.join(ROOT, "apps.yml"))

    assert_includes source, "android:"
    assert_includes source, "ios:"
    assert_includes source, "certificate_env:"
    assert_includes source, "team_id_env:"
  end
end
