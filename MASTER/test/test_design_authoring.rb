# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/design/authoring"

class DesignAuthoringTest < Minitest::Test
  Authoring = Master::Design::Authoring

  def test_frontend_source_under_rails_is_briefed
    path = "/repo/RAILS/brgen/app/views/posts/index.html.erb"
    text = Authoring.context(path:)

    assert_includes text, "DESIGN AUTHORING"
    assert_includes text, "purpose=read and participate in a post stream"
    assert_includes text, Master::Design::Typeface::HOUSE_RULE
    assert_includes text, "AVOID THE DEFAULTS"
  end

  def test_bsdports_is_not_held_to_the_house_typeface
    text = Authoring.context(path: "/repo/RAILS/bsdports/app/assets/stylesheets/application.scss")

    assert_includes text, "DESIGN AUTHORING"
    refute_includes text, Master::Design::Typeface::HOUSE_RULE
  end

  def test_ruby_generated_and_vendored_files_get_nothing
    assert_equal "", Authoring.context(path: "/repo/RAILS/brgen/app/models/post.rb")
    assert_equal "", Authoring.context(path: "/repo/RAILS/master_web/public/face.runtime.js")
    assert_equal "", Authoring.context(path: "/repo/RAILS/brgen/vendor/x.css")
    assert_equal "", Authoring.context(path: "/repo/MASTER/lib/x.js")
  end

  def test_route_follows_the_view_path
    assert_equal "/posts", Authoring.route_for(%w[brgen app views posts index.html.erb])
    assert_equal "/items/new", Authoring.route_for(%w[brgen app views items new.html.erb])
    assert_equal "/", Authoring.route_for(%w[brgen app assets a.css])
  end
end

class DesignMissionTest < Minitest::Test
  Authoring = Master::Design::Authoring

  def test_goal_naming_an_app_gets_its_direction
    text = Authoring.mission_context(goal: "complete the amber wardrobe stylesheet")

    assert_includes text, "DESIGN MISSION"
    assert_includes text, "aesthetic_direction=editorial_wardrobe"
    assert_includes text, Master::Design::Typeface::HOUSE_RULE
  end

  def test_goal_without_an_app_keeps_the_app_independent_half
    text = Authoring.mission_context(goal: "design a landing page")

    assert_includes text, "DESIGN MISSION"
    refute_includes text, "aesthetic_direction="
    assert_includes text, "AVOID THE DEFAULTS"
  end

  def test_frontend_nouns_route_to_the_design_intent
    router = Master::CLI::IntentRouter.new

    assert_equal :design_frontend, router.classify("rewrite the brgen landing stylesheet")
    assert_equal :medium, router.risk(:design_frontend)
    assert_equal :run_ui_review, router.classify("review the design look")
  end

  def notes(memory) = memory.context.map(&:text).join("\n")

  def test_bridge_seeds_the_brief_only_for_design_missions
    memory = Master::Core::Memory.new(risk: :low)
    record = { "operator" => { "intent" => "design_frontend" } }
    Master::CLI::CoreBridge.seed_design_brief(memory, "fix the brgen homepage css", record, root: Master::ROOT)

    assert_match(/design: DESIGN MISSION/, notes(memory))

    other = Master::Core::Memory.new(risk: :low)
    Master::CLI::CoreBridge.seed_design_brief(other, "x", { "operator" => { "intent" => "unknown" } }, root: Master::ROOT)

    refute_match(/DESIGN MISSION/, notes(other))
  end
end
