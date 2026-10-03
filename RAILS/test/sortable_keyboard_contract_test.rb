# frozen_string_literal: true

require "minitest/autorun"

class SortableKeyboardContractTest < Minitest::Test
  ROOT = File.expand_path("../shared", __dir__)
  VENDOR = File.join(ROOT, "vendor/javascript/@stimulus-components--sortable.js")
  OUTFIT_VIEW = File.expand_path("../../amber/app/views/outfits/show.html.erb", __dir__)
  VARIANT_VIEW = File.expand_path("../../brgen/engines/marketplace/app/views/marketplace/variants/index.html.erb", __dir__)

  def test_shared_sortable_has_a_visible_keyboard_reorder_path
    source = File.read(VENDOR)

    assert_includes source, 'this.element.addEventListener("keydown", this.onKeyboardReorder)'
    assert_includes source, 'event.key !== "ArrowUp"'
    assert_includes source, 'event.key !== "ArrowDown"'
    assert_includes source, 'item.tabIndex = 0'
    assert_includes source, 'item.setAttribute("aria-keyshortcuts", "ArrowUp ArrowDown")'
    assert_includes source, 'this.installKeyboardControls()'
    assert_includes source, 'button.textContent = delta < 0 ? "↑" : "↓"'
    assert_includes source, 'this.identifier'
    assert_includes source, 'moveBy'
    assert_includes source, 'await this.onUpdate({ item, newIndex: nextIndex })'
  end
  def test_keyboard_contract_covers_both_existing_sortable_surfaces
    outfit = File.read(OUTFIT_VIEW)
    variants = File.read(VARIANT_VIEW)

    assert_includes outfit, 'data-controller="outfit-sortable"'
    assert_includes outfit, 'data-sortable-move-up-label-value='
    assert_includes outfit, 'data-sortable-move-down-label-value='
    assert_includes variants, 'data-controller="sortable"'
    assert_includes variants, 'data-sortable-resource-name-value="variant"'
    assert_includes variants, 'data-sortable-move-up-label-value='
    assert_includes variants, 'data-sortable-move-down-label-value='
  end
end
