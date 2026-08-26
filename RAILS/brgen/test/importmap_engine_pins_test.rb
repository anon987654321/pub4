# frozen_string_literal: true

require "test_helper"

# Every vertical's Stimulus controllers must be pinned, not merely servable.
#
# `pin_all_from "app/javascript/controllers"` resolves its path against
# Rails.root, so it covers brgen's own controllers and nothing else. Each engine
# pushes its app/javascript onto config.assets.paths, which makes those files
# reachable over HTTP — but importmap needs a *pin* for the module specifier to
# exist, and stimulus-loading's eagerLoadControllersFrom("controllers") only
# walks what the importmap declares. So an engine controller was downloadable and
# registered nowhere: no error, no 404, no console warning, a
# data-controller attribute that nothing answered.
#
# Measured before the fix: 91 imports, 19 under controllers/, zero from any
# engine. After: 95, 23, and four — dating_intro, marketplace_logo,
# playlist_player, tv_player. Those are the dating landing-page toggle, the
# marketplace animated logo, the playlist audio player and the TV video player on
# all three watch pages, every one of them inert in production.
#
# This asserts the outcome rather than the mechanism, so it survives a rewrite of
# how the pinning is done and fails if a vertical is added without pinning.
class ImportmapEnginePinsTest < ActiveSupport::TestCase
  VERTICALS = %w[dating marketplace playlist takeaway tv].freeze

  def imports
    @imports ||= JSON.parse(
      Rails.application.importmap.to_json(resolver: ApplicationController.helpers),
    ).fetch("imports", {})
  end

  def controller_specifiers
    imports.keys.select { |key| key.start_with?("controllers/") }
  end

  # Guards the guard: if this ever reads zero controllers the assertions below
  # would pass vacuously for the wrong reason.
  test "the importmap resolves and declares brgen's own controllers" do
    refute_empty imports, "importmap resolved to nothing — the check, not the tree"
    assert_operator controller_specifiers.size, :>=, 15,
                    "expected brgen's own controllers/* pins; got #{controller_specifiers.size}"
  end

  test "every engine that ships Stimulus controllers has them pinned" do
    shipping = VERTICALS.select do |vertical|
      Dir.glob(Rails.root.join("engines", vertical, "app/javascript/controllers/*_controller.js")).any?
    end
    refute_empty shipping, "no engine ships controllers — the glob is wrong, not the tree"

    unpinned = shipping.reject do |vertical|
      controller_specifiers.any? { |spec| spec.include?(vertical) }
    end

    assert_empty unpinned, <<~MSG.strip
      these engines ship Stimulus controllers that the importmap does not pin:

        #{unpinned.join(", ")}

      Their files are servable but no module specifier exists, so
      eagerLoadControllersFrom never registers them and every data-controller
      referring to them is dead. pin_all_from resolves against Rails.root — an
      engine needs its own absolute root. See config/importmap.rb.
    MSG
  end

  # Named individually because each is a user-visible surface someone reported
  # working from the source alone.
  test "the four controllers that were dead in production are pinned" do
    %w[dating_intro marketplace_logo playlist_player tv_player].each do |name|
      assert_includes controller_specifiers, "controllers/#{name}_controller",
                      "#{name} is unpinned again — it was inert in production before this was fixed"
    end
  end
end
