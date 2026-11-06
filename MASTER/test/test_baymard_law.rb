# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/configuration_guard"
require_relative "../lib/review/baymard_law"
require "digest"
require "yaml"

class TestBaymardLaw < Minitest::Test
  def with_fixture
    Dir.mktmpdir("baymard-law") do |dir|
      master = File.join(dir, "MASTER")
      rails = File.join(dir, "RAILS", "demo")
      FileUtils.mkdir_p(File.join(master, "data"))
      FileUtils.mkdir_p(File.join(rails, "config"))
      FileUtils.mkdir_p(File.join(rails, "app", "views", "layouts"))
      FileUtils.mkdir_p(File.join(rails, "app", "views", "demo"))
      FileUtils.mkdir_p(File.join(rails, "app", "assets", "stylesheets"))

      profile = fixture_profile
      law_ids = (profile.fetch("checks").values.flat_map { |row| Array(row["law_ids"]) } +
        [profile.dig("research", "authority_law")]).uniq
      laws = law_ids.to_h { |id| [id, { "statement" => "Fixture law #{id}" }] }
      File.write(File.join(master, "data", "laws.yml"), YAML.dump(laws))
      File.write(File.join(rails, "config", "routes.rb"), "Rails.application.routes.draw { root 'demo#index' }\n")
      File.write(File.join(dir, "RAILS", "apps.yml"), YAML.dump("apps" => { "demo" => {} }))

      yield dir, rails, profile
    end
  end

  def fixture_profile
    {
      "schema" => 1,
      "research" => {
        "provider" => "Baymard Institute",
        "authority_law" => "EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY",
        "scope" => "Profile validation fixture.",
        "methodology_url" => "https://baymard.com/research/methodology",
        "benchmark_url" => "https://baymard.com/ux-benchmark",
        "checkout_research_url" => "https://baymard.com/research-articles/ecommerce-checkout-usability-report-and-benchmark",
        "cart_abandonment_url" => "https://baymard.com/lists/cart-abandonment-rate",
        "inline_validation_url" => "https://baymard.com/research-articles/inline-form-validation",
        "reviewed_on" => "2026-11-01",
        "boundary" => "Independent test profile; not an official Baymard audit.",
      },
      "checks" => {
        "form_control_names" => source_rule("forms", "REACH_form_label"),
        "image_alternatives" => source_rule("images", "REACH_img_alt"),
        "interactive_names" => source_rule("controls", "REACH_aria_labels"),
        "native_click_targets" => source_rule("controls", "POLA_intuitive_navigation"),
        "focus_visibility" => source_rule("accessibility", "REACH_focus_visible"),
        "mobile_viewport" => source_rule("mobile", "REACH_touch_target_min"),
        "navigation_findability" => task_rule("navigation", "POLA_intuitive_navigation"),
      },
      "evidence_policy" => {
        "required" => {
          "source" => {
            "pass" => %w[source_files source_inventory_sha256],
            "finding" => %w[finding_path line source_sha256],
          },
          "task" => %w[method participants summary artifacts sha256],
        },
        "task_privacy" => "Use anonymised aggregate observations only; redact images and screen captures.",
        "verdicts" => %w[pass fail inconclusive not_applicable],
      },
    }
  end

  def source_rule(area, law_id)
    {
      "area" => area,
      "mode" => "source",
      "applies_when" => "all",
      "severity" => "error",
      "law_ids" => [law_id],
      "statement" => "Fixture source requirement.",
      "verification" => "Inspect the rendered result.",
    }
  end

  def task_rule(area, law_id)
    {
      "area" => area,
      "mode" => "task",
      "applies_when" => "all",
      "severity" => "warning",
      "law_ids" => [law_id],
      "statement" => "Fixture task requirement.",
      "task" => "Give a participant a realistic navigation task.",
      "verification" => "Record the task and evidence.",
    }
  end

  def write_good_surface(rails)
    layout = File.join(rails, "app", "views", "layouts", "application.html.erb")
    page = File.join(rails, "app", "views", "demo", "index.html.erb")
    css = File.join(rails, "app", "assets", "stylesheets", "application.css")
    File.write(layout, '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><%= yield %></body></html>')
    File.write(page, <<~HTML)
      <form>
        <label for="email">Email</label>
        <input id="email" type="email">
        <button type="submit">Continue</button>
        <img src="/logo.svg" alt="Demo service">
      </form>
    HTML
    File.write(css, ".control { outline: 2px solid currentColor; }\n")
  end

  def test_profile_is_valid_and_every_criterion_resolves_to_a_law
    with_fixture do |dir, _rails, profile|
      assert Master::Review::BaymardLaw.validate_profile!(profile, root: File.join(dir, "MASTER"))
    end
  end

  def test_profile_refuses_a_phantom_law_reference
    with_fixture do |dir, _rails, profile|
      profile.fetch("checks").fetch("navigation_findability")["law_ids"] = ["MADE_UP_LAW"]

      error = assert_raises(Master::Review::BaymardLaw::InvalidProfile) do
        Master::Review::BaymardLaw.validate_profile!(profile, root: File.join(dir, "MASTER"))
      end

      assert_match(/MADE_UP_LAW/, error.message)
    end
  end

  def test_source_defects_fail_while_unobserved_navigation_remains_inconclusive
    with_fixture do |dir, rails, profile|
      File.write(File.join(rails, "app", "views", "layouts", "application.html.erb"), "<html><body><%= yield %></body></html>")
      File.write(File.join(rails, "app", "views", "demo", "index.html.erb"), <<~HTML)
        <form><input type="email"><button type="submit">Continue</button></form>
        <img src="/product.jpg">
        <div onclick="submitOrder()">Continue</div>
      HTML
      File.write(File.join(rails, "app", "assets", "stylesheets", "application.css"), ".control { outline: none; }\n")

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "fail", outcomes.fetch("form_control_names")
      assert_equal "fail", outcomes.fetch("image_alternatives")
      assert_equal "fail", outcomes.fetch("native_click_targets")
      assert_equal "fail", outcomes.fetch("focus_visibility")
      assert_equal "fail", outcomes.fetch("mobile_viewport")
      assert_equal "inconclusive", outcomes.fetch("navigation_findability")
      assert_operator report.findings.size, :>=, 5
      assert report.findings.any? { |finding| finding.evidence.any? { |item| item.start_with?("finding_path=") } }
      assert report.findings.any? { |finding| finding.evidence.any? { |item| item.start_with?("line=") } }
      assert report.findings.any? { |finding| finding.evidence.any? { |item| item.start_with?("source_sha256=") } }
      assert_operator report.inconclusive_count, :>=, 1
      assert_nil report.to_h.fetch("official_baymard_score")
    end
  end

  # ERB interpolations inside a tag must not hide the attributes that follow:
  # `%>` once ended tag extraction and the interior quotes broke attribute
  # parsing, so every dynamically-sourced view failed as unnamed. The mask keeps
  # offsets and reads dynamic values as present, leaving rendered evidence to
  # resolve them.
  def test_erb_interpolated_attributes_stay_inspectable
    with_fixture do |dir, rails, profile|
      File.write(File.join(rails, "app", "views", "demo", "index.html.erb"), <<~HTML)
        <img loading="lazy" src="<%= edition.hero_url %>" alt="<%= edition.hero_alt %>" width="620">
        <input type="checkbox" value="<%= report.id %>" aria-label="<%= t("a11y.report", id: report.id) %>">
        <input id="map-search" type="search" placeholder="<%= t("search.places") %>"
          aria-label="<%= t("search.places") %>">
        <img src="/decorative.jpg" alt="">
      HTML
      File.write(File.join(rails, "app", "views", "layouts", "application.html.erb"),
        "<html><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" \
        "<body><%= yield %></body></html>")

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "pass", outcomes.fetch("image_alternatives")
      assert_equal "pass", outcomes.fetch("form_control_names")
    end
  end

  # `data-action="input->auto-submit#submit"` carries a `>` inside a quoted
  # attribute value. The `[^>]*>` tag reader ended the tag on that arrow and
  # dropped every attribute after it, so this very control — named with an
  # aria-label that only the arrow hid — read as unnamed.
  def test_quoted_arrow_inside_attribute_value_no_longer_truncates_the_tag
    with_fixture do |dir, rails, profile|
      File.write(File.join(rails, "app", "views", "demo", "index.html.erb"), <<~HTML)
        <form action="/search" method="get">
          <input type="search" name="q" placeholder="Search"
            data-action="input->auto-submit#submit" aria-label="Search query">
        </form>
      HTML

      File.write(File.join(rails, "app", "views", "layouts", "application.html.erb"), <<~HTML)
        <html><meta name="viewport" content="width=device-width, initial-scale=1"><body><%= yield %></body></html>
      HTML

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "pass", outcomes.fetch("form_control_names")
    end
  end

  # A layout that renders its viewport meta through ERB (`<%= tag.meta name: "viewport" ... %>`)
  # has no inspectable meta element in source — that is an unknown the rendered
  # review resolves, not a fail on a declaration the source plainly makes.
  def test_erb_rendered_viewport_is_unknown_not_a_failed_layout
    with_fixture do |dir, rails, profile|
      viewport = <<~HTML
        <html><head><%= tag.meta name: "viewport",
          content: "width=device-width, initial-scale=1, viewport-fit=cover" %></head><body><%= yield %></body></html>
      HTML
      File.write(File.join(rails, "app", "views", "layouts", "application.html.erb"), viewport)

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "inconclusive", outcomes.fetch("mobile_viewport")
      assert_empty report.findings.select { |finding| finding.check_id == "mobile_viewport" }
    end
  end

  def test_good_markup_passes_source_probes_but_does_not_invent_user_testing
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "pass", outcomes.fetch("form_control_names")
      assert_equal "pass", outcomes.fetch("image_alternatives")
      assert_equal "pass", outcomes.fetch("mobile_viewport")
      assert_equal "pass", outcomes.fetch("native_click_targets")
      assert_equal "inconclusive", outcomes.fetch("navigation_findability")
      form = report.assessments.find { |item| item.check_id == "form_control_names" }
      assert form.evidence.any? { |item| item.start_with?("source_inventory_sha256=") }
      assert_empty report.findings
    end
  end

  def test_task_evidence_rejects_personal_identifiers_and_unredacted_contact_details
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      artifact_path = File.join(dir, "navigation-observation.md")
      File.write(artifact_path, "Anonymised aggregate observation.\n")
      digest = Digest::SHA256.file(artifact_path).hexdigest
      evidence_path = File.join(dir, "baymard-evidence.yml")
      base = {
        "status" => "pass",
        "method" => "moderated_user_test",
        "participants" => 2,
        "summary" => "Observed 2026-11-01: two participants found the destination without prompting.",
        "artifacts" => [{ "path" => "navigation-observation.md", "sha256" => digest }],
      }
      evidence = {
        "schema" => 1,
        "apps" => { "demo" => { "navigation_findability" => base.merge("participant_name" => "Private") } },
      }
      File.write(evidence_path, YAML.dump(evidence))
      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      row = report.assessments.find { |item| item.check_id == "navigation_findability" }
      assert_equal "inconclusive", row.status
      assert_match(/anonymised aggregate/, row.summary)

      evidence["apps"]["demo"]["navigation_findability"] = base.merge(
        "summary" => "Contact jane@example.com after the test."
      )
      File.write(evidence_path, YAML.dump(evidence))
      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      row = report.assessments.find { |item| item.check_id == "navigation_findability" }
      assert_equal "inconclusive", row.status
      assert_match(/contact details/, row.summary)
    end
  end

  def test_task_pass_requires_method_participant_and_hash_verified_artifact
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      artifact_path = File.join(dir, "navigation-observation.md")
      File.write(artifact_path, "Participant found the destination without prompting.\n")
      digest = Digest::SHA256.file(artifact_path).hexdigest
      evidence_path = File.join(dir, "baymard-evidence.yml")
      File.write(evidence_path, YAML.dump(
        "schema" => 1,
        "apps" => {
          "demo" => {
            "navigation_findability" => {
              "status" => "pass",
              "method" => "expert_walkthrough",
              "participants" => 1,
              "summary" => "The participant found the destination without prompting.",
              "artifacts" => [{ "path" => "navigation-observation.md", "sha256" => digest }],
            },
          },
        },
      ))

      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      navigation = report.assessments.find { |item| item.check_id == "navigation_findability" }

      assert_equal "pass", navigation.status
      assert navigation.evidence.any? { |item| item.start_with?("navigation-observation.md sha256=") }
      assert_includes navigation.evidence.first, Digest::SHA256.hexdigest(File.read(artifact_path))
    end
  end

  def test_task_artifacts_are_scanned_bounded_and_redacted
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      artifact_path = File.join(dir, "navigation-observation.md")
      evidence_path = File.join(dir, "baymard-evidence.yml")
      evidence = {
        "schema" => 1,
        "apps" => {
          "demo" => {
            "navigation_findability" => {
              "status" => "pass",
              "method" => "expert_walkthrough",
              "participants" => 1,
              "summary" => "The task completed without prompting.",
              "artifacts" => [],
            },
          },
        },
      }

      File.write(artifact_path, "Observed contact: jane@example.com\n")
      evidence["apps"]["demo"]["navigation_findability"]["artifacts"] = [{
        "path" => "navigation-observation.md",
        "sha256" => Digest::SHA256.file(artifact_path).hexdigest,
      }]
      File.write(evidence_path, YAML.dump(evidence))
      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      row = report.assessments.find { |item| item.check_id == "navigation_findability" }
      assert_equal "inconclusive", row.status
      assert_match(/artifact/, row.summary)

      File.write(artifact_path, "participant: Jane Doe\\n")
      evidence["apps"]["demo"]["navigation_findability"]["artifacts"][0]["sha256"] =
        Digest::SHA256.file(artifact_path).hexdigest
      File.write(evidence_path, YAML.dump(evidence))
      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      row = report.assessments.find { |item| item.check_id == "navigation_findability" }
      assert_equal "inconclusive", row.status
      assert_match(/artifact/, row.summary)

      screenshot_path = File.join(dir, "screen.png")
      File.binwrite(screenshot_path, "\x89PNG\r\n\x1a\n".b + "redacted fixture bytes".b)
      evidence["apps"]["demo"]["navigation_findability"]["artifacts"] = [{
        "path" => "screen.png",
        "sha256" => Digest::SHA256.file(screenshot_path).hexdigest,
      }]
      File.write(evidence_path, YAML.dump(evidence))
      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      row = report.assessments.find { |item| item.check_id == "navigation_findability" }
      assert_equal "inconclusive", row.status
      assert_match(/redaction declaration/, row.summary)

      evidence["apps"]["demo"]["navigation_findability"]["artifacts"][0]["redacted"] = true
      File.write(evidence_path, YAML.dump(evidence))
      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      row = report.assessments.find { |item| item.check_id == "navigation_findability" }
      assert_equal "pass", row.status
      assert_match(/redacted=true/, row.evidence.join(" "))
    end
  end

  def test_oversized_task_artifacts_cannot_prove_a_task
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      artifact_path = File.join(dir, "large-observation.md")
      File.binwrite(artifact_path, "x" * (Master::Review::BaymardLaw::MAX_EVIDENCE_ARTIFACT_BYTES + 1))
      evidence_path = File.join(dir, "baymard-evidence.yml")
      File.write(evidence_path, YAML.dump(
        "schema" => 1,
        "apps" => {
          "demo" => {
            "navigation_findability" => {
              "status" => "pass",
              "method" => "expert_walkthrough",
              "participants" => 1,
              "summary" => "The task completed without prompting.",
              "artifacts" => [{
                "path" => "large-observation.md",
                "sha256" => Digest::SHA256.file(artifact_path).hexdigest,
              }],
            },
          },
        },
      ))

      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      row = report.assessments.find { |item| item.check_id == "navigation_findability" }

      assert_equal "inconclusive", row.status
      assert_match(/size/, row.summary)
    end
  end

  def test_wrong_artifact_hash_cannot_prove_a_task
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      artifact_path = File.join(dir, "navigation-observation.md")
      File.write(artifact_path, "Observed route.\n")
      evidence_path = File.join(dir, "baymard-evidence.yml")
      File.write(evidence_path, YAML.dump(
        "schema" => 1,
        "apps" => {
          "demo" => {
            "navigation_findability" => {
              "status" => "pass",
              "method" => "moderated_user_test",
              "participants" => 1,
              "summary" => "The task completed.",
              "artifacts" => [{ "path" => "navigation-observation.md", "sha256" => "0" * 64 }],
            },
          },
        },
      ))

      report = Master::Review::BaymardLaw.new(
        root: dir, apps: ["demo"], evidence_path: "baymard-evidence.yml", profile:
      ).call
      navigation = report.assessments.find { |item| item.check_id == "navigation_findability" }

      assert_equal "inconclusive", navigation.status
      assert_match(/artifact hash/, navigation.summary)
    end
  end

  def test_haml_markup_remains_inconclusive_until_the_rendered_tree_is_inspected
    with_fixture do |dir, rails, profile|
      html_layout = File.join(rails, "app", "views", "layouts", "application.html.erb")
      FileUtils.rm_f(html_layout)
      haml = File.join(rails, "app", "views", "layouts", "application.html.haml")
      File.write(haml, "!!!\n%html\n  %head\n  %body\n    = yield\n")

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "inconclusive", outcomes.fetch("form_control_names")
      assert_equal "inconclusive", outcomes.fetch("image_alternatives")
      assert_equal "inconclusive", outcomes.fetch("interactive_names")
      assert_equal "inconclusive", outcomes.fetch("mobile_viewport")

      manual = "rendered_review=RAILS/demo/app/views/layouts/application.html.haml"
      form = report.assessments.find { |item| item.check_id == "form_control_names" }
      assert_includes form.evidence, manual
    end
  end

  def test_source_read_errors_name_the_repository_relative_file
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      oversized = File.join(rails, "app", "views", "demo", "oversized.html.erb")
      File.write(oversized, "x" * (Master::Review::BaymardLaw::MAX_SOURCE_BYTES + 1))

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call

      assert report.read_errors.any? { |error| error.start_with?("RAILS/demo/app/views/demo/oversized.html.erb:") }
    end
  end

  def test_clickable_custom_elements_require_rendered_keyboard_verification
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      page = File.join(rails, "app", "views", "demo", "index.html.erb")
      File.write(page, <<~HTML)
        <button type="button">Continue</button>
        <div role="button" tabindex="0" onclick="continueFlow()">More</div>
      HTML

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      row = report.assessments.find { |item| item.check_id == "native_click_targets" }

      assert_equal "inconclusive", row.status
      assert_match(/rendered inspection/, row.summary)
    end
  end

  def test_evidence_file_symlink_cannot_escape_the_repository
    with_fixture do |dir, _rails, profile|
      outside = Dir.mktmpdir("baymard-evidence-outside")
      begin
        target = File.join(outside, "evidence.yml")
        File.write(target, YAML.dump("schema" => 1, "apps" => {}))
        File.symlink(target, File.join(dir, "evidence-link.yml"))

        audit = Master::Review::BaymardLaw.new(
          root: dir, apps: ["demo"], evidence_path: "evidence-link.yml", profile:
        )
        error = assert_raises(Master::Review::BaymardLaw::InvalidEvidence) { audit.call }
        assert_match(/symlink escapes/, error.message)
      ensure
        FileUtils.remove_entry(outside) if File.directory?(outside)
      end
    end
  end

  def test_commerce_journeys_are_scoped_to_routes_and_view_paths_not_incidental_copy
    with_fixture do |dir, rails, _profile|
      stylesheet = File.join(rails, "app", "assets", "stylesheets", "application.css")
      File.write(stylesheet, "/* Search cart checkout products are mentioned in this design note. */\n")
      product_view = File.join(rails, "app", "views", "products", "show.html.erb")
      FileUtils.mkdir_p(File.dirname(product_view))
      File.write(product_view, "<h1>Product details</h1>\n")

      inventory = Master::Review::BaymardLaw::SourceInventory.new(
        repo_root: dir, rails_root: File.join(dir, "RAILS")
      ).call
      features = inventory.apps.find { |app| app.name == "demo" }.features

      assert features.fetch(:product)
      refute features.fetch(:search)
      refute features.fetch(:cart)
      refute features.fetch(:checkout)
    end
  end

  def test_shared_engine_does_not_receive_standalone_participant_tasks
    with_fixture do |dir, _rails, profile|
      shared = File.join(dir, "RAILS", "__shared")
      FileUtils.mkdir_p(File.join(shared, "config"))
      FileUtils.mkdir_p(File.join(shared, "app", "views", "layouts"))
      FileUtils.mkdir_p(File.join(shared, "app", "views", "shared"))
      File.write(File.join(shared, "config", "routes.rb"), "Rails.application.routes.draw { root 'shared#index' }\n")
      File.write(
        File.join(shared, "app", "views", "layouts", "application.html.erb"),
        '<html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><%= yield %></body></html>',
      )
      File.write(
        File.join(shared, "app", "views", "shared", "index.html.erb"),
        '<button type="button">Continue</button>',
      )

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["__shared"], profile:).call
      task = report.assessments.find { |item| item.check_id == "navigation_findability" }

      assert_equal "not_applicable", task.status
      assert_match(/consuming applications/, task.summary)
    end
  end

  def test_aria_labelledby_references_are_verified_or_left_inconclusive
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      page = File.join(rails, "app", "views", "demo", "index.html.erb")
      File.write(page, <<~HTML)
        <input type="email" aria-labelledby="missing-email-label">
        <button aria-labelledby="missing-button-label"></button>
      HTML

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "inconclusive", outcomes.fetch("form_control_names")
      assert_equal "inconclusive", outcomes.fetch("interactive_names")
    end
  end

  def test_aria_labelledby_with_present_text_is_a_valid_source_name
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      page = File.join(rails, "app", "views", "demo", "index.html.erb")
      File.write(page, <<~HTML)
        <span id="email-label">Email address</span>
        <input type="email" aria-labelledby="email-label">
        <span id="continue-label">Continue</span>
        <button aria-labelledby="continue-label"></button>
      HTML

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "pass", outcomes.fetch("form_control_names")
      assert_equal "pass", outcomes.fetch("interactive_names")
    end
  end

  def test_whitespace_image_alt_and_closed_unrelated_labels_are_not_accepted
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      page = File.join(rails, "app", "views", "demo", "index.html.erb")
      File.write(page, <<~HTML)
        <label for="other">Other field</label>
        <input id="email" type="email">
        <img src="/product.jpg" alt="   ">
      HTML

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      outcomes = report.assessments.to_h { |item| [item.check_id, item.status] }

      assert_equal "fail", outcomes.fetch("form_control_names")
      assert_equal "fail", outcomes.fetch("image_alternatives")
    end
  end

  def test_wrapping_label_with_text_names_a_control_without_an_id
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      page = File.join(rails, "app", "views", "demo", "index.html.erb")
      File.write(page, '<label>Email address <input type="email"></label>')

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      form = report.assessments.find { |item| item.check_id == "form_control_names" }

      assert_equal "pass", form.status
      assert_empty report.findings.select { |finding| finding.check_id == "form_control_names" }
    end
  end

  def test_empty_associated_and_wrapping_labels_do_not_name_controls
    with_fixture do |dir, rails, profile|
      write_good_surface(rails)
      page = File.join(rails, "app", "views", "demo", "index.html.erb")
      File.write(page, <<~HTML)
        <label for="email"></label>
        <input id="email" type="email">
        <label><input type="text"></label>
      HTML

      report = Master::Review::BaymardLaw.new(root: dir, apps: ["demo"], profile:).call
      form = report.assessments.find { |item| item.check_id == "form_control_names" }

      assert_equal "fail", form.status
      assert_equal 2, report.findings.count { |finding| finding.check_id == "form_control_names" }
    end
  end

  def test_the_live_profile_is_accepted_by_configuration_guard
    path = Master.data_path("baymard_ux.yml")
    content = File.read(path, encoding: "UTF-8")

    assert_nil Master::ConfigurationGuard.validate(path:, content:)
  end
end
