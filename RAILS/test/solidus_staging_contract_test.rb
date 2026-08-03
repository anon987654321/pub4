# frozen_string_literal: true

require "minitest/autorun"

# Staging-prep contract for Solidus (no gem install required).
# Full cutover is operator-run on a non-1GB host — see brgen/docs/SOLIDUS_MARKETPLACE.md.
class SolidusStagingContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BRGEN = File.join(ROOT, "brgen")

  def test_gemfile_gates_solidus_behind_env_flag
    gemfile = File.read(File.join(BRGEN, "Gemfile"))
    assert_includes gemfile, 'ENV["SOLIDUS_MARKETPLACE"] == "1"'
    assert_includes gemfile, 'gem "solidus"'
    assert_includes gemfile, "solidus_starter_frontend"
    assert_includes gemfile, "solidus_marketplace"
  end

  def test_initializer_defines_status_helper
    init = File.read(File.join(BRGEN, "config/initializers/solidus_marketplace.rb"))
    assert_includes init, "module SolidusMarketplace"
    assert_includes init, "def mountable?"
    assert_includes init, 'ENV["SOLIDUS_MARKETPLACE"]'
  end

  # The marketplace vertical became a mountable engine, and the Solidus mount
  # went with it. Read the host's routes plus the engine's, which is the app's
  # actual routing surface.
  def test_routes_mount_only_when_mountable
    routes = [File.join(BRGEN, "config/routes.rb"), *Dir.glob(File.join(BRGEN, "engines/*/config/routes.rb")).sort]
             .select { |f| File.file?(f) }.map { |f| File.read(f) }.join("\n")
    assert_includes routes, "Brgen::SolidusMarketplace.mountable?"
    assert_includes routes, "Spree::Core::Engine"
    assert_includes routes, 'at: "/solidus"'
  end

  def test_docs_and_apps_yml_track_planned_mount
    docs = File.read(File.join(BRGEN, "docs/SOLIDUS_MARKETPLACE.md"))
    apps = File.read(File.join(ROOT, "apps.yml"))
    assert_includes docs, "SOLIDUS_MARKETPLACE=1"
    assert_match(/1.?GB OpenBSD VPS/, docs)
    assert_match(/solidus core mount/, apps)
    assert_match(/status: planned/, apps)
  end

  def test_schema_has_no_spree_tables_by_default
    schema = File.read(File.join(BRGEN, "db/schema.rb"))
    refute_match(/create_table "spree_/, schema, "spree tables must not land without staged solidus:install")
  end
end
