# frozen_string_literal: true

require "test_helper"

# A confirmation is a toast that leaves on its own; an alert and a notice
# carrying an undo stay in the page, because neither may run on a timer.
class FlashToastTest < ActionView::TestCase
  test "a plain notice renders as a self-dismissing toast and not inline" do
    flash[:notice] = I18n.t("items.undo_restore")

    render partial: "shared/flash_toasts"
    assert_includes rendered, %(class="toast-stack")
    assert_includes rendered, %(data-controller="toast")
    assert_includes rendered, "data-turbo-temporary"
    assert_includes rendered, I18n.t("items.undo_restore")

    render partial: "shared/flash"
    assert_not_includes rendered, "flash--notice"
  end

  test "a notice carrying an undo stays inline with its button" do
    flash[:notice] = I18n.t("items.undo_restore")
    flash[:undo] = { "path" => "/items/1/restore", "label" => I18n.t("items.undo_restore") }

    render partial: "shared/flash_toasts"
    assert_not_includes rendered, "toast-stack"

    render partial: "shared/flash"
    assert_includes rendered, "flash--notice"
    assert_includes rendered, "flash-undo"
  end

  test "an alert stays inline and never becomes a toast" do
    flash[:alert] = I18n.t("shared.flash.not_authorized")

    render partial: "shared/flash_toasts"
    assert_not_includes rendered, "toast-stack"

    render partial: "shared/flash"
    assert_includes rendered, %(role="alert")
  end
end
