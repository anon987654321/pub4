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
      law_ids = profile.fetch("checks").values.flat_map { |row| Array(row["law_ids"]) }.uniq
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
        "scope" => "Profile validation fixture.",
        "methodology_url" => "https://baymard.com/research/methodology",
        "benchmark_url" => "https://baymard.com/ux-benchmark",
        "reviewed_on" => "2026-11-01",
        "boundary" => "Independent test profile; not an official benchmark.",
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
      assert_operator report.inconclusive_count, :>=, 1
      assert_nil report.to_h.fetch("official_baymard_score")
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
      assert_equal "inconclusive", outcomes.fetch("navigation_findability")
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
        "summary" => "Two participants found the destination without prompting.",
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
      assert_includes navigation.evidence, "navigation-observation.md"
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

  def test_the_live_profile_is_accepted_by_configuration_guard
    path = Master.data_path("baymard_ux.yml")
    content = File.read(path, encoding: "UTF-8")

    assert_nil Master::ConfigurationGuard.validate(path:, content:)
  end
end
