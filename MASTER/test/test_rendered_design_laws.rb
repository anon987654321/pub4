# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "yaml"
require File.expand_path("../checks/support/cdp_session", __dir__)
require File.expand_path("../checks/support/rendered_design/capture", __dir__)

# Every rendered design-book Law, proved in a real browser: its bad page (fixtures/
# rendered_design_laws.yml) rendered headless at 390x844 must give the Law a finding and its
# good page none, read through the Law itself as the scanner reads a .rendered.json snapshot.
# Without Chrome each test is skipped as INCONCLUSIVE; it never passes on a page it did not render.
class TestRenderedDesignLaws < Minitest::Test
  FIXTURES = YAML.safe_load_file(File.expand_path("fixtures/rendered_design_laws.yml", __dir__), aliases: true)
  PAGES = FIXTURES.fetch("pages")
  SNAPSHOT = "MASTER/var/rendered/fixture.rendered.json"
  LINKS = (1..30).map { |n| %(<li><a href="#l#{n}" style="display:block;height:60px">Lenke #{n}</a></li>) }.join

  def self.browser
    @browser ||= Deploy::CdpSession.new.start.tap { |cdp| Minitest.after_run { cdp.close } }
  end

  def document(body, name)
    page = body.gsub("{{self}}", name).gsub("{{links}}", LINKS).gsub("{{padding}}", "Fyll " * 2000)
    FIXTURES.fetch("document").sub("{{page}}", page)
  end

  def snapshot(id, variant:, dir:)
    row = PAGES.fetch(id)
    name = "#{id}.#{variant}.html"
    File.write(File.join(dir, name), document(row.fetch(variant), name))
    plan = Deploy::RenderedDesign::Capture::Plan.new(widths: [390], motion_ms: row.fetch("motion_ms", 0),
                                                     phases: row.fetch("phases").map(&:to_sym), budget: row["budget"])
    Deploy::RenderedDesign::Capture.snapshot(self.class.browser, "file://#{File.join(dir, name)}", plan)
  end

  def judged(id, variant)
    Dir.mktmpdir("rendered-law") { |dir| law_findings(id, snapshot(id, variant:, dir:).to_json, path: SNAPSHOT) }
  end

  PAGES.each_key do |id|
    define_method("test_#{id.downcase}_flags_its_bad_page_and_passes_its_good_page") do
      skip "INCONCLUSIVE: no headless Chrome to render #{id}" unless Deploy::CdpSession.available?

      refute_empty judged(id, "bad"), "#{id}: bad page rendered with no finding"
      assert_empty judged(id, "good"), "#{id}: good page flagged"
    end
  end

  def test_every_rendered_evaluator_has_a_page
    assert_equal Deploy::RenderedDesign.ids.sort, PAGES.keys.sort
  end
end
