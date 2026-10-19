# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/design_scope"

class TestDesignScope < Minitest::Test
  SCOPE = Master::Fix::DesignScope

  def test_a_path_inside_one_rails_app_names_that_app
    assert_equal %w[brgen], SCOPE.apps_for("RAILS/brgen")
    assert_equal %w[amber], SCOPE.apps_for("RAILS/amber/app/assets/stylesheets/application.scss")
    assert_equal %w[brgen], SCOPE.apps_for("/work/pub4/RAILS/brgen/app/views")
  end

  def test_several_targets_name_each_app_once
    assert_equal %w[brgen amber], SCOPE.apps_for("RAILS/brgen RAILS/amber RAILS/brgen/app")
  end

  # The loop measures one rendered app at a time: a target that names no app names none.
  def test_a_target_that_names_no_single_app_names_none
    ["", "RAILS", "all", "MASTER", "OPENBSD RAILS", "RAILS/__shared/app/assets", "MASTER/lib/RAILSY"].each do |target|
      assert_empty SCOPE.apps_for(target), target.inspect
    end
  end
end
