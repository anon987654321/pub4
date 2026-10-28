# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"
require File.expand_path("../tools/rails/visual_seed", __dir__)

# The local seed's safety and its undo, with a recording runner standing in for
# bin/rails: nothing here boots an app or touches a real database.
class TestVisualSeed < Minitest::Test
  def tree
    Dir.mktmpdir("seed-tree") do |root|
      FileUtils.mkdir_p(File.join(root, "RAILS"))
      File.write(File.join(root, "RAILS", "apps.yml"), { "apps" => { "brgen" => { "port" => 1 }, "amber" => { "port" => 2 }, "bsdports" => { "port" => 3 } } }.to_yaml)
      %w[brgen amber bsdports].each { |app| FileUtils.mkdir_p(File.join(root, "RAILS", app, "storage")) }
      yield root
    end
  end

  def seeder(root, ran, serving: false, fail_on: nil)
    runner = lambda do |app, env, task|
      ran << [app, task, env["SEED_SCALE"]]
      File.write(File.join(root, "RAILS", app, "storage", "development.sqlite3"), "seeded") unless task == fail_on
      task != fail_on
    end
    out = StringIO.new
    [Deploy::VisualSeed.new(root:, out:, runner:, serving: ->(_port) { serving }), out]
  end

  def db(root, app) = File.join(root, "RAILS", app, "storage", "development.sqlite3")

  def test_without_yes_it_plans_and_runs_nothing
    tree do |root|
      ran = []
      seed, out = seeder(root, ran)
      assert_equal 0, seed.seed(%w[amber])
      assert_empty ran
      assert_match(/would seed amber/, out.string)
    end
  end

  def test_seed_backs_up_labels_and_unseed_restores
    tree do |root|
      File.write(db(root, "amber"), "mine")
      ran = []
      seed, = seeder(root, ran)
      assert_equal 0, seed.seed(%w[amber], scale: 3, yes: true)
      assert_equal [["amber", "db:prepare", "3"], ["amber", "db:seed", "3"]], ran
      assert_equal "seeded", File.read(db(root, "amber"))
      label = JSON.parse(File.read(seed.marker("amber")))
      assert_equal 3, label["scale"]
      seed.unseed(%w[amber])
      assert_equal "mine", File.read(db(root, "amber"))
      refute File.exist?(seed.marker("amber"))
    end
  end

  def test_seeding_twice_is_a_no_op
    tree do |root|
      ran = []
      seed, out = seeder(root, ran)
      seed.seed(%w[bsdports], yes: true)
      count = ran.size
      seed.seed(%w[bsdports], yes: true)
      assert_equal count, ran.size
      assert_match(/already seeded/, out.string)
    end
  end

  def test_a_serving_app_is_not_seeded
    tree do |root|
      ran = []
      seed, out = seeder(root, ran, serving: true)
      seed.seed(%w[brgen], yes: true)
      assert_empty ran
      assert_match(/serving on its port/, out.string)
    end
  end

  def test_a_failed_seed_puts_the_database_back
    tree do |root|
      File.write(db(root, "amber"), "mine")
      seed, out = seeder(root, [], fail_on: "db:seed")
      refute_equal 0, seed.seed(%w[amber], yes: true)
      assert_equal "mine", File.read(db(root, "amber"))
      assert_match(/failed; its database is back/, out.string)
    end
  end

  def test_unknown_apps_and_a_database_url_are_refused
    previous = ENV["DATABASE_URL"]
    tree do |root|
      seed, = seeder(root, [])
      assert_raises(ArgumentError) { seed.seed(%w[master], yes: true) }
      ENV["DATABASE_URL"] = "postgres://prod"
      assert_equal 2, seed.seed(%w[amber], yes: true)
    end
  ensure
    ENV["DATABASE_URL"] = previous
  end
end
