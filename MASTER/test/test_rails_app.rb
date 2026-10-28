# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require_relative "../lib/fix/rails_app"

class TestRailsApp < Minitest::Test
  RailsApp = Master::Fix::RailsApp

  def test_named_apps_uses_the_canonical_registry_in_stable_order
    with_repository do |root|
      assert_equal %w[amber brgen], RailsApp.named_apps(repo_root: root)
    end
  end

  def test_app_name_only_returns_registry_entries
    with_repository do |root|
      assert_equal "amber", RailsApp.app_name("RAILS/amber/app/models/item.rb", repo_root: root)
      assert_equal "brgen", RailsApp.app_name(File.join(root, "RAILS/brgen/Gemfile"), repo_root: root)
      assert_nil RailsApp.app_name("RAILS/master/public/face.css", repo_root: root)
      assert_nil RailsApp.app_name("MASTER/lib/fix/rails_app.rb", repo_root: root)
    end
  end

  def test_app_root_requires_a_registered_app_root_directory
    with_repository do |root|
      assert RailsApp.app_root?("RAILS/amber", repo_root: root)
      refute RailsApp.app_root?("RAILS/amber/app", repo_root: root)
      refute RailsApp.app_root?("RAILS/master", repo_root: root)
      FileUtils.rm_rf(File.join(root, "RAILS/brgen"))
      refute RailsApp.app_root?("RAILS/brgen", repo_root: root)
    end
  end

  def test_tree_target_is_rails_scoped_and_rejects_paths_outside_repository
    with_repository do |root|
      assert RailsApp.tree_target?("RAILS", repo_root: root)
      assert RailsApp.tree_target?("RAILS/amber/app", repo_root: root)
      refute RailsApp.tree_target?("MASTER", repo_root: root)
      refute RailsApp.tree_target?(File.expand_path("../outside", root), repo_root: root)
    end
  end

  # Rails is read from the tree: an engine counts, a tree-level file under RAILS counts, and a
  # Rails project beside the checkout does not make MASTER Rails.
  def test_tree_target_reads_rails_from_the_files
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, "RAILS", "brgen_maps", "lib", "maps"))
      File.write(File.join(root, "RAILS", "brgen_maps", "lib", "maps", "engine.rb"), "module Maps; end\n")
      FileUtils.mkdir_p(File.join(root, "MASTER", "lib"))

      assert RailsApp.tree_target?("RAILS/brgen_maps/app/models/place.rb", repo_root: root)
      assert RailsApp.tree_target?("RAILS/test/check_test.rb", repo_root: root)
      refute RailsApp.tree_target?("MASTER/lib", repo_root: root)
    end
  end

  def test_invalid_app_registry_fails_loudly
    Dir.mktmpdir("rails-app-registry-invalid") do |root|
      FileUtils.mkdir_p(File.join(root, "RAILS"))
      File.write(File.join(root, "RAILS", "apps.yml"), "not_apps: true\n")

      error = assert_raises(KeyError) { RailsApp.named_apps(repo_root: root) }
      assert_includes error.message, "apps"
    end
  end

  def with_repository
    Dir.mktmpdir("rails-app-registry") do |root|
      rails = File.join(root, "RAILS")
      FileUtils.mkdir_p(rails)
      File.write(File.join(rails, "apps.yml"), "apps:\n  amber: {}\n  brgen: {}\n")

      %w[amber brgen].each do |name|
        app_root = File.join(rails, name)
        FileUtils.mkdir_p(File.join(app_root, "bin"))
        File.write(File.join(app_root, "Gemfile"), "source \"https://rubygems.org\"\n")
        File.write(File.join(app_root, "bin", "rails"), "#!/usr/bin/env ruby\n")
        FileUtils.mkdir_p(File.join(app_root, "config"))
        File.write(File.join(app_root, "config", "application.rb"), "module App; end\n")
      end

      yield root
    end
  end

end
