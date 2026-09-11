# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/schema_migration"

# Four defects that all read as "the app is fine" until something migrates.
#
# A schema.rb pinned behind its own migrations, two migrations creating one
# table, a route pointing at a controller nobody wrote, and a column declared
# twice on one table. Each is planted here, proved to fail the gate, then
# removed and proved to pass.
#
# The gate walks the fleet through Deploy::Inventory, which reads apps.yml under
# a ROOT constant fixed at load time. There is no root argument, so the fixture
# tree is installed by rewriting ROOT and RAILS_ROOT around the call.
class SchemaMigrationGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::SchemaMigrationGate
  VERSION = "20260101000000"

  # A tree the gate calls clean, so each test can spoil exactly one thing.
  def sound_tree(dir)
    plant_apps_yml(dir, "demo")
    plant(dir, "RAILS/demo/db/schema.rb", schema(VERSION, "posts", %w[title body]))
    plant(dir, "RAILS/demo/db/migrate/#{VERSION}_create_posts.rb", migration("posts"))
    plant(dir, "RAILS/demo/config/routes.rb", %(Rails.application.routes.draw do\n  get "/p", to: "posts#index"\nend\n))
    plant(dir, "RAILS/demo/app/controllers/posts_controller.rb", "class PostsController; end\n")
  end

  def schema(version, table, columns)
    body = columns.map { |name| %(    t.string "#{name}"\n) }.join
    "ActiveRecord::Schema[8.0].define(version: #{version}) do\n" +
      %(  create_table "#{table}", force: :cascade do |t|\n) + body + "  end\nend\n"
  end

  # The symbol form, because that is what every migration in this fleet writes.
  # The scan read a colon as an opening delimiter and demanded a quote to close
  # it, so this fixture had to use quotes to be seen at all.
  def migration(table, body = nil)
    "class Create#{table.capitalize} < ActiveRecord::Migration[8.0]\n" \
      "  def change\n    #{body || "create_table :#{table}"}\n  end\nend\n"
  end

  def gate_over
    Dir.mktmpdir do |dir|
      sound_tree(dir)
      yield dir
      with_constants(GATE, ROOT: dir, RAILS_ROOT: File.join(dir, "RAILS")) { GATE.run }
    end
  end

  def test_a_sound_tree_passes_and_says_it_measured_something
    result = gate_over { nil }

    assert result.ok?, result.failures.join(", ")
    assert_equal 1, result.checks_ran
  end

  def test_a_schema_behind_its_latest_migration_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/demo/db/migrate/20260202000000_add_slug.rb", migration("slugs"))
    end

    refute result.ok?, "a schema pinned behind its migrations passed"
    assert_match(/schema version #{VERSION} != latest migration 20260202000000/, result.failures.first)
  end

  def test_two_migrations_creating_one_table_fail
    result = gate_over do |dir|
      plant(dir, "RAILS/demo/db/migrate/#{VERSION}_create_posts.rb", migration("posts"))
      plant(dir, "RAILS/demo/db/migrate/20260102000000_create_posts_again.rb", migration("posts"))
      plant(dir, "RAILS/demo/db/schema.rb", schema("20260102000000", "posts", %w[title body]))
    end

    refute result.ok?, "a table created twice passed"
    assert(result.failures.any? { |line| line.match?(/second create_table posts/) }, result.failures.join(", "))
  end

# Sixteen second create_table calls exist across this fleet and every one is
  # guarded. A check that counted calls would fail all sixteen; this one reads
  # the guard, so each of the three forms in use here is spared.
  GUARDS = [
    "create_table :posts, if_not_exists: true",
    "return if table_exists?(:posts)\n    create_table :posts",
    "drop_table :posts if table_exists?(:posts)\n    create_table :posts",
  ].freeze

  def test_a_second_create_table_is_spared_when_the_migration_expects_one
    GUARDS.each do |guard|
      result = gate_over do |dir|
        plant(dir, "RAILS/demo/db/migrate/20260102000000_again.rb", migration("posts", guard))
        plant(dir, "RAILS/demo/db/schema.rb", schema("20260102000000", "posts", %w[title body]))
      end

      spared = result.failures.none? { |line| line.include?("create_table posts") }
      assert spared, "#{guard[0, 40]} is a guard this fleet uses: #{result.failures.join(", ")}"
    end
  end

  def test_a_route_naming_a_controller_nobody_wrote_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/demo/config/routes.rb",
            %(Rails.application.routes.draw do\n  get "/g", to: "ghosts#index"\nend\n))
    end

    refute result.ok?, "a route to a missing controller passed"
    assert_match(%r{route target ghosts#index missing controller}, result.failures.first)
  end

  # Nested controllers resolve through the glob, so a namespaced target must not
  # be reported as missing just because the directory is not the flat one.
  def test_a_namespaced_route_target_resolves_to_a_nested_controller
    result = gate_over do |dir|
      plant(dir, "RAILS/demo/config/routes.rb",
            %(Rails.application.routes.draw do\n  get "/a", to: "admin/reports#index"\nend\n))
      plant(dir, "RAILS/demo/app/controllers/admin/reports_controller.rb", "class ReportsController; end\n")
    end

    assert result.ok?, result.failures.join(", ")
  end

  def test_a_column_declared_twice_on_one_table_fails
    result = gate_over do |dir|
      plant(dir, "RAILS/demo/db/schema.rb", schema(VERSION, "posts", %w[title title]))
    end

    refute result.ok?, "a column declared twice passed"
    assert_match(/duplicate column title on posts/, result.failures.first)
  end

  # No apps is an unread inventory rather than a clean fleet.
  def test_an_empty_inventory_is_inconclusive
    result = Dir.mktmpdir do |dir|
      plant(dir, "RAILS/apps.yml", "apps: {}\n")
      with_constants(GATE, ROOT: dir, RAILS_ROOT: File.join(dir, "RAILS")) { GATE.run }
    end

    assert_equal :inconclusive, result.outcome
    assert_match(/nothing was read/, result.unchecked.first)
  end
end
