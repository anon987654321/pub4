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

  # The quoted table name. The gate's duplicate-table scan requires a closing
  # quote, so a migration written `create_table :posts` is invisible to it —
  # which is every migration in this repository, and a finding recorded in
  # TODO.md rather than pinned here as if it were intended.
  def migration(table)
    "class Create#{table.capitalize} < ActiveRecord::Migration[8.0]\n" +
      %(  def change\n    create_table "#{table}"\n  end\nend\n)
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
    assert(result.failures.any? { |line| line.match?(/duplicate create_table posts/) }, result.failures.join(", "))
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
