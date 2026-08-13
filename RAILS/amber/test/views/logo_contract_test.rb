# frozen_string_literal: true

require "test_helper"

# Contract: Amber logo geometry and gradient match the canonical Caprasimo swoosh design.
class LogoContractTest < ActionView::TestCase
  test "logo partial matches canonical swoosh path and white hairlines" do
    render partial: "shared/logo", locals: { id_prefix: "test" }
    html = rendered

    assert_includes html, 'viewBox="0 0 1000 500"'
    # Through the key. This asserted the English literal "Amber Logo with Retro
    # Lines" and broke the moment the aria-label became t("amber.logo_aria") in
    # the 2026-08-12 i18n pass — mine, and the third test this week found pinning
    # an untranslated string in place. The <title> below is not translated and is
    # asserted literally, which is the difference: one is chrome a screen reader
    # reads aloud, the other is an internal name.
    assert_includes html, I18n.t("amber.logo_aria")
    assert_includes html, "Amber Logo - Nice Version"
    assert_includes html, 'd="M50,220 C250,180 750,180 950,220"'
    assert_includes html, 'startOffset="2%"'
    assert_includes html, ">amber<"
    assert_includes html, 'dx="10" dy="-40"'
    assert_includes html, "animated-gradient"
    assert_includes html, 'stroke="#FFFFFF"'
    assert_includes html, 'stroke-width="0.5"'
    assert_includes html, 'stroke-width="4"'
    assert_includes html, 'd="M50,238 C200,158 400,258 600,158 S850,218 950,188"'
    assert_includes html, "Caprasimo"
  end

  test "logo uses unique ids per instance" do
    render partial: "shared/logo", locals: { id_prefix: "a" }
    first = rendered
    render partial: "shared/logo", locals: { id_prefix: "b" }
    second = rendered

    assert_includes first, "a-swoosh-path"
    assert_includes first, "a-text-mask"
    assert_includes second, "b-swoosh-path"
    assert_includes second, "b-text-mask"
  end

  test "public brand icons exist with amber palette" do
    root = Rails.root.join("public")
    %w[icon.svg icon.png icon-192.png apple-touch-icon.png favicon.ico].each do |name|
      path = root.join(name)
      assert File.file?(path), "missing #{name}"
      assert File.size?(path).to_i.positive?, "empty #{name}"
    end
    svg = File.read(root.join("icon.svg"))
    assert_includes svg, "#FFB999"
    assert_includes svg, "#99E6E6"
    assert_includes svg, "Amber"
  end
end
