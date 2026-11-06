# frozen_string_literal: true

require_relative "test_helper"
require "erb"
require File.expand_path("../checks/support/cdp_session", __dir__)
require File.expand_path("../checks/support/axe", __dir__)

# axe-core vendored and run in the page over CDP, its rules mapped onto the Laws.
class TestAxe < Minitest::Test
  AXE = Deploy::Axe
  PAGE = <<~HTML
    <!doctype html><html lang="nb"><head><title>Fixture</title></head>
    <body><main><h1>Fixture</h1><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">
    <button></button></main></body></html>
  HTML

  def test_the_vendored_file_is_axe_core_with_its_licence
    assert_match(/\A\/\*! axe v4\.\d+\.\d+/, File.read(AXE::SOURCE, 40))
    assert_match(/Mozilla Public License, version 2\.0/, File.read(File.join(File.dirname(AXE::SOURCE), "LICENSE"), 60))
  end

  def test_violations_are_named_under_the_law_that_owns_the_rule
    report = { "violations" => [
      { "id" => "image-alt", "impact" => "critical", "nodes" => 2, "target" => "main > img" },
      { "id" => "duplicate-id-aria", "impact" => "serious", "nodes" => 1, "target" => "#x" },
    ] }

    assert_equal ["accessibility_axe: a/b/mobile image-alt x2 (critical) - main > img law=IMG_ALT",
                  "accessibility_axe: a/b/mobile duplicate-id-aria x1 (serious) - #x law=unmapped"],
                 AXE.findings("a/b/mobile", report)
  end

  # The real thing, once: Chrome loads the fixture, axe runs inside it, no node involved.
  def test_axe_runs_in_a_real_page_over_cdp
    skip "no Chrome here" unless Deploy::CdpSession.available?

    cdp = Deploy::CdpSession.new
    cdp.start
    cdp.navigate("data:text/html,#{ERB::Util.url_encode(PAGE)}")
    rules = AXE.run(cdp).fetch("violations").to_h { |row| [row["id"], AXE.law(row["id"])] }

    assert_equal "IMG_ALT", rules["image-alt"]
    assert_equal "ARIA_LABELS", rules["button-name"]
  ensure
    cdp&.close
  end
end
