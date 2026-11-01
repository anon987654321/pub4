# frozen_string_literal: true

require_relative "test_helper"

class TestBaymardAudit < Minitest::Test
  Audit = Master::BaymardAudit

  def test_profile_is_original_and_every_check_maps_to_existing_laws
    document, digest = Audit.profile

    assert_equal 1, document.fetch("schema")
    assert_equal "Baymard Institute", document.dig("research", "provider")
    assert_match(/\A[0-9a-f]{64}\z/, digest)
    assert document.dig("research", "boundary").match?(/not an official Baymard audit/i)
    assert Audit.validate_profile!(document)
  end

  def test_clean_source_markup_passes_the_deterministic_checks
    report = audit_with(<<~HTML)
      <!doctype html>
      <html lang="en">
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body>
          <label for="email">Email address</label>
          <input id="email" name="email" type="email">
          <img src="/product.webp" alt="Blue wool coat">
          <a href="/products/coat">View coat</a>
          <button type="button">Add to list</button>
        </body>
      </html>
    HTML

    source = report.findings.select { |finding| finding.mode == "source" }
    assert_operator source.size, :>=, 4
    assert source.all?(&:pass?), source.reject(&:pass?).map(&:to_h).inspect
    assert_equal "INCONCLUSIVE", report.status,
                 "a source pass must not certify browser behaviour or participant research"
  end

  def test_missing_labels_alternatives_and_names_are_findings
    report = audit_with(<<~HTML)
      <!doctype html>
      <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body>
          <input id="email" name="email">
          <img src="/coat.webp">
          <a href="/next"><svg aria-hidden="true"></svg></a>
          <button type="button"><svg aria-hidden="true"></svg></button>
        </body>
      </html>
    HTML

    failures = report.findings.select(&:fail?)
    assert_includes failures.map(&:check_id), "form_control_names"
    assert_includes failures.map(&:check_id), "image_alternatives"
    assert_includes failures.map(&:check_id), "interactive_names"
    assert_equal "FAIL", report.status
  end

  def test_empty_alt_is_a_valid_decorative_image_declaration
    report = audit_with(<<~HTML)
      <!doctype html>
      <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body><img src="/ornament.svg" alt=""></body>
      </html>
    HTML

    assert_empty report.findings.select { |finding| finding.check_id == "image_alternatives" && finding.fail? }
  end

  def test_dynamic_erb_control_content_is_inconclusive_not_a_false_pass
    report = audit_with(<<~HTML)
      <!doctype html>
      <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body><a href="/account"><%= t(".account_link") %></a></body>
      </html>
    HTML

    row = report.findings.find { |finding| finding.check_id == "interactive_names" }
    assert_equal "INCONCLUSIVE", row.status
    assert_match(/generated dynamically/, row.message)
  end

  def test_mobile_and_human_research_remain_inconclusive_without_evidence
    report = audit_with(<<~HTML)
      <!doctype html>
      <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body><a href="/home">Home</a></body>
      </html>
    HTML

    %w[native_click_targets focus_visibility mobile_viewport first_screen_purpose
       navigation_findability mobile_task_completion keyboard_and_assistive_technology].each do |id|
      row = report.findings.find { |finding| finding.check_id == id }
      assert_equal "INCONCLUSIVE", row.status, "#{id} was promoted without evidence"
    end
  end

  def test_context_specific_tasks_only_apply_when_the_project_has_that_flow
    Dir.mktmpdir("baymard-ux") do |rails|
      view = File.join(rails, "demo", "app", "views", "products", "show.html.erb")
      FileUtils.mkdir_p(File.dirname(view))
      File.write(view, "<main><h1>Coat</h1></main>")
      report = Audit.audit_tree(rails_root: rails, apps: %w[demo])

      ids = report.findings.map(&:check_id)
      assert_includes ids, "product_evaluation"
      refute_includes ids, "checkout_guest_and_recovery"
      assert_includes report.contexts.fetch("demo"), "product"
    end
  end

  def test_manual_evidence_requires_an_observed_participant_task
    evidence = {
      "demo" => {
        "first_screen_purpose" => {
          "status" => "PASS",
          "observed_at" => "2026-11-01T10:00:00Z",
          "method" => "moderated_task",
          "participant_count" => 3,
          "tasks" => ["Explain the service and identify the primary action"],
          "summary" => "All three participants identified the service and next action without prompting.",
          "artifact_sha256" => "a" * 64,
        },
      },
    }
    report = audit_with("<html><head><meta name='viewport' content='width=device-width'></head><body></body></html>", evidence:)
    row = report.findings.find { |finding| finding.check_id == "first_screen_purpose" }

    assert_equal "PASS", row.status
    assert_equal 3, row.evidence.fetch("participant_count")
  end

  def test_rendered_evidence_must_name_the_declared_instrument_and_surface
    evidence = {
      "demo" => {
        "focus_visibility" => {
          "status" => "PASS",
          "observed_at" => "2026-11-01T10:00:00Z",
          "instrument" => "some-other-check",
          "surfaces" => ["/"],
          "summary" => "Focus rings appeared.",
          "artifact_sha256" => "b" * 64,
        },
      },
    }
    report = audit_with("<html><head><meta name='viewport' content='width=device-width'></head><body></body></html>", evidence:)
    row = report.findings.find { |finding| finding.check_id == "focus_visibility" }

    assert_equal "FAIL", row.status
    assert_match(/instrument does not match/, row.message)
  end

  def test_task_evidence_does_not_accept_participant_identity_fields
    evidence = {
      "demo" => {
        "first_screen_purpose" => {
          "status" => "PASS",
          "observed_at" => "2026-11-01T10:00:00Z",
          "method" => "moderated_task",
          "participant_count" => 1,
          "tasks" => ["Explain the service"],
          "summary" => "Task completed.",
          "artifact_sha256" => "c" * 64,
          "participant_name" => "Not allowed",
        },
      },
    }
    report = audit_with("<html><head><meta name='viewport' content='width=device-width'></head><body></body></html>", evidence:)
    row = report.findings.find { |finding| finding.check_id == "first_screen_purpose" }

    assert_equal "FAIL", row.status
    assert_match(/unknown evidence field/, row.message)
  end

  private

  def audit_with(markup, evidence: {})
    Dir.mktmpdir("baymard-ux") do |rails|
      path = File.join(rails, "demo", "app", "views", "layouts", "application.html.erb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, markup)
      return Audit.audit_tree(rails_root: rails, apps: %w[demo], evidence:)
    end
  end
end
