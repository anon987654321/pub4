# frozen_string_literal: true

require "test_helper"
require_relative "../../test/engine_roots"

# Engine JavaScript can be servable through the asset paths and still be missing
# from the importmap. In that case data-controller looks normal, but Stimulus
# never imports the controller and the interaction is silently inert.
#
# The host's relative pin_all_from only covers brgen/app/javascript/controllers.
# Every sibling engine must be pinned from its own root. Assert actual module
# specifiers derived from every controller filename, not an engine-name substring
# or a hard-coded controller count.
class ImportmapEnginePinsTest < ActiveSupport::TestCase
  def imports
    @imports ||= JSON.parse(
      Rails.application.importmap.to_json(resolver: ApplicationController.helpers),
    ).fetch("imports", {})
  end

  def controller_specifiers
    imports.keys.select { |key| key.start_with?("controllers/") }
  end

  test "the importmap resolves and declares brgen's own controllers" do
    refute_empty imports, "importmap resolved to nothing — the check, not the tree"
    assert_operator controller_specifiers.size, :>=, 15,
                    "expected brgen's own controllers/* pins; got #{controller_specifiers.size}"
  end

  test "every engine controller file has its exact importmap pin" do
    expected = EngineRoots::ASSET_PATHS.flat_map do |vertical, relative_root|
      root = Rails.root.join("..", relative_root, "app/javascript/controllers").to_s
      Dir.glob(File.join(root, "**", "*_controller.js")).sort.map do |path|
        relative = path.delete_prefix("#{root}/").delete_suffix(".js")
        [ vertical, "controllers/#{relative}" ]
      end
    end

    refute_empty expected, "no engine controllers were found — the scan roots are wrong, not the tree"

    missing = expected.reject { |_vertical, specifier| controller_specifiers.include?(specifier) }
    assert_empty missing.map { |vertical, specifier| "#{vertical}: #{specifier}" }, <<~MSG.strip
      These engine controllers have no resolved importmap pin:

        #{missing.map { |vertical, specifier| "#{vertical}: #{specifier}" }.join("\n")}

      Adding an asset path makes a file servable, not importable. Keep each engine
      root in config/importmap.rb and pin its controllers under controllers/.
    MSG
  end

  test "known user-facing vertical controllers remain pinned" do
    %w[marketplace_logo playlist_player tv_player].each do |name|
      assert_includes controller_specifiers, "controllers/#{name}_controller",
                      "#{name} is unpinned and its visible control would be inert"
    end
  end
end
