# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/artifact_preservation"
require_relative "../lib/fix/task_contract"
require_relative "../lib/fix/kernel/repair_adapter"

class TestArtifactPreservation < Minitest::Test
  GUARD = Master::Fix::ArtifactPreservation

  BEFORE = <<~HTML
    <!doctype html>
    <html lang="no">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="/assets/site.css">
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <style>h1 { font-family: "EB Garamond", serif; }</style>
      </head>
      <body>
        <header class="masthead"><h1>Old heading</h1></header>
        <main id="content"><p>Old paragraph</p></main>
        <script>window.siteReady = true;</script>
      </body>
    </html>
  HTML

  def test_content_only_accepts_text_changes_without_changing_markup_or_style
    after = BEFORE.sub("Old heading", "New heading").sub("Old paragraph", "New paragraph")
    result = GUARD.verify(before: BEFORE, after:, intent: "content_only", format: "html")
    assert_equal "PASS", result.status
    assert_includes result.checks, "html_markup"
  end

  def test_content_only_rejects_class_or_structure_changes
    after = BEFORE.sub('class="masthead"', 'class="new-masthead"')
    result = GUARD.verify(before: BEFORE, after:, intent: "content_only", format: "html")
    assert_equal "FAIL", result.status
  end

  def test_content_only_rejects_inline_font_changes
    after = BEFORE.sub('"EB Garamond"', "Arial")
    result = GUARD.verify(before: BEFORE, after:, intent: "content_only", format: "html")
    assert_equal "FAIL", result.status
  end

  def test_content_and_structure_allows_body_markup_but_preserves_behavior_and_visual_contract
    after = BEFORE.sub('<main id="content"><p>Old paragraph</p></main>',
                       '<main id="content"><section><p>New paragraph</p></section></main>')
    result = GUARD.verify(before: BEFORE, after:, intent: "content_and_structure", format: "html")
    assert_equal "PASS", result.status
  end

  def test_content_and_structure_rejects_external_script_source_change
    before = BEFORE.sub("<script>", '<script src="/assets/app.js">')
    after = BEFORE.sub("<script>", '<script src="/assets/other.js">')
    result = GUARD.verify(before:, after:, intent: "content_and_structure", format: "html")
    assert_equal "FAIL", result.status
  end

  def test_content_and_structure_rejects_changed_image_asset_reference
    before = BEFORE.sub("</main>", '<img src="/assets/brand.svg" alt="Brand"></main>')
    after = before.sub("/assets/brand.svg", "/assets/other.svg")
    result = GUARD.verify(before:, after:, intent: "content_and_structure", format: "html")
    assert_equal "FAIL", result.status
  end

  def test_content_and_structure_rejects_inline_behavior_change
    after = BEFORE.sub("window.siteReady = true", "window.siteReady = false")
    result = GUARD.verify(before: BEFORE, after:, intent: "content_and_structure", format: "html")
    assert_equal "FAIL", result.status
  end

  def test_functional_change_requires_rendered_evidence_when_stylesheet_changes
    result = GUARD.verify(before: "body { color: black; }", after: "body { color: blue; }",
                          intent: "functional_change", format: "css")
    assert_equal "INCONCLUSIVE", result.status
  end

  def test_protected_asset_must_remain_byte_identical
    result = GUARD.verify(
      before: BEFORE,
      after: BEFORE,
      intent: "content_only",
      format: "html",
      protected_assets: [{ path: "site.css", before: "h1 { color: black; }", after: "h1 { color: blue; }" }],
    )
    assert_equal "FAIL", result.status
  end

  def test_changed_office_document_without_parser_is_inconclusive
    result = GUARD.verify(before: "binary-before", after: "binary-after",
                          intent: "content_only", format: "docx")
    assert_equal "INCONCLUSIVE", result.status
  end

  def test_repair_adapter_vetoes_content_only_html_markup_changes_before_write
    contract = Master::Fix::TaskContract.build(
      intent: "content_only", scope: ["page.html"], preserve: [], proof: []
    )
    adapter = Master::Fix::Kernel::RepairAdapter.allocate
    adapter.instance_variable_set(:@visual_custody, nil)
    adapter.instance_variable_set(:@bus, nil)
    rejected = []
    adapter.define_singleton_method(:reject_preservation) do |path, result|
      rejected << [path, result.status, result.reason]
      false
    end
    path = File.join(Master::REPO_ROOT, "page.html")
    after = BEFORE.sub('class="masthead"', 'class="new-masthead"')

    outcome = Master::Fix::TaskContract.with_current(contract) do
      adapter.send(:assess_artifact_preservation, path, BEFORE, after)
    end

    assert_equal :rejected, outcome
    assert_equal 1, rejected.size
    assert_equal "FAIL", rejected.first[1]
  end

  def test_unsupported_source_format_is_recorded_as_inconclusive_not_pass
    contract = Master::Fix::TaskContract.build(
      intent: "functional_change", scope: ["worker.rb"], preserve: [], proof: []
    )
    adapter = Master::Fix::Kernel::RepairAdapter.allocate
    adapter.instance_variable_set(:@visual_custody, nil)
    adapter.instance_variable_set(:@bus, nil)
    path = File.join(Master::REPO_ROOT, "worker.rb")

    evidence = Master::Fix::TaskContract.with_current(contract) do
      adapter.send(:assess_artifact_preservation, path, "before", "after")
      Master::Fix::TaskContract.preservation_evidence
    end

    assert_equal "INCONCLUSIVE", evidence.fetch("status")
    assert_equal "INCONCLUSIVE", evidence.fetch("results").first.fetch("status")
  end

  def test_redesign_requires_rendered_and_accessibility_review
    result = GUARD.verify(before: BEFORE, after: BEFORE, intent: "redesign", format: "html")
    assert_equal "INCONCLUSIVE", result.status
  end
end
