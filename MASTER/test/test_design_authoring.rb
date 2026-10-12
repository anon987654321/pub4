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
