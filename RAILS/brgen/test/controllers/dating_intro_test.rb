# frozen_string_literal: true

require "test_helper"

# dating_intro_controller.js has no JavaScript test, so this holds the half a
# request can see: the deck page mounts it, gives it both targets it reads, and
# every action the markup names is a method the controller defines. Delete this
# with the controller if the intro goes.
class DatingIntroTest < ActionDispatch::IntegrationTest
  CONTROLLER = Rails.root.join("engines/dating/app/javascript/controllers/dating_intro_controller.js")

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "dating.brgen.no"
  end

  test "the deck mounts the intro controller with the targets and actions it defines" do
    source = File.read(CONTROLLER)
    declared_targets = source[/static targets = \[([^\]]*)\]/, 1].to_s.scan(/"(\w+)"/).flatten
    defined_methods = source.scan(/^  (\w+)\(/).flatten

    get dating.root_path
    assert_response :success

    assert_select "[data-controller~='dating-intro']", 1
    %w[intro discover].each do |target|
      assert_includes declared_targets, target
      assert_select "[data-controller~='dating-intro'] [data-dating-intro-target='#{target}']", 1
    end

    actions = css_select("[data-action*='dating-intro#']").flat_map { |node| node["data-action"].scan(/dating-intro#(\w+)/).flatten }
    refute_empty actions, "the intro section no longer wires any gesture to the controller"
    assert_empty actions - defined_methods, "actions with no method in dating_intro_controller.js"
  end
end
