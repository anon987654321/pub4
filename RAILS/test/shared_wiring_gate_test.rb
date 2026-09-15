# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class SharedWiringGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_shared_wiring_gate_lib_exists
    path = File.join(ROOT, "gates/lib/source/shared_wiring.rb")
    assert File.file?(path)
  end

  def test_release_gate_calls_domain_alignment_in_process
    source = File.read(File.join(ROOT, "gates/release.rb"))
    assert_includes source, "Deploy::DomainAlignmentGate"
    assert_includes source, "gate.run"
    refute_includes source, '"domain_alignment_gate.rb"'
  end

  def test_manifest_registers_shared_wiring_gate
    row = YAML.safe_load_file(File.join(ROOT, "gates/gates.yml")).fetch("shared_wiring")

    assert_equal "lib/source/shared_wiring", row.fetch("require")
    assert_equal "Deploy::SharedWiringGate", row.fetch("class")
  end

  def test_shared_wiring_gate_checks_extended_shared_artifacts
    source = File.read(File.join(ROOT, "gates/lib/source/shared_wiring.rb"))
    %w[omniauth.rb auth_extensions.rb Shared::ReactionsController production_baseline.rb REQUIRED_SHARED_CONTROLLERS].each do |needle|
      assert_includes source, needle
    end
  end

  def test_shared_wiring_gate_forbids_local_orphan_js_copies
    source = File.read(File.join(ROOT, "gates/lib/source/shared_wiring.rb"))
    %w[
      FORBIDDEN_APP_JS
      controllers/hello_controller.js
      idb-keyval.js
      controllers/bottom_sheet_controller.js
      controllers/offline_feed_controller.js
    ].each do |needle|
      assert_includes source, needle
    end
  end

  def test_apps_have_no_forbidden_local_js
    %w[amber brgen bsdports].each do |app|
      %w[
        controllers/hello_controller.js
        idb-keyval.js
        controllers/bottom_sheet_controller.js
        controllers/offline_feed_controller.js
      ].each do |rel|
        path = File.join(ROOT, app, "app/javascript", rel)
        refute File.file?(path), "#{app} still has local #{rel}"
      end
    end
  end

  ERROR_PAGES = Dir[File.join(ROOT, "{amber,brgen,bsdports,shared}/public/*.html")].freeze
  ERRORS_CSS = File.read(File.join(ROOT, "shared/public/styles/errors.css"))

  def declared(css) = css.scan(/(--[\w-]+)\s*:/).flatten

  # A static error page renders when the app does not, so nothing but errors.css
  # and the page's own <style> can supply a colour. Every custom property the
  # page reads has to be declared by one of the two, or it falls back to nothing.
  def test_error_pages_read_only_custom_properties_something_declares
    refute_empty ERROR_PAGES
    ERROR_PAGES.each do |page|
      html = File.read(page)
      missing = html.scan(/var\((--[\w-]+)\)/).flatten.uniq - declared(ERRORS_CSS) - declared(html)

      assert_empty missing, "#{page} reads #{missing.join(", ")}, which neither errors.css nor the page declares"
    end
  end

  # The apps default to Norwegian, and the error pages are the one surface I18n
  # cannot reach.
  def test_error_pages_speak_norwegian
    ERROR_PAGES.each do |page|
      assert_match(/<html lang="nb"/, File.read(page), "#{page} is not a Norwegian page")
    end
  end

  # overlay_shared_public copies shared/public over each app's public on deploy,
  # so a page shared carries replaces the page an app carries for itself.
  def test_shared_carries_no_error_page_an_app_carries
    shared = Dir[File.join(ROOT, "shared/public/*.html")].map { |path| File.basename(path) }
    %w[amber brgen bsdports].each do |app|
      clobbered = shared & Dir[File.join(ROOT, app, "public/*.html")].map { |path| File.basename(path) }

      assert_empty clobbered, "shared/public would overwrite #{app}'s #{clobbered.join(", ")} on deploy"
    end
  end
end
