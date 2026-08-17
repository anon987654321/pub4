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
end
