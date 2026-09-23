# frozen_string_literal: true

require "minitest/autorun"

class TestStimulusComponentsPreference < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_gate_has_explicit_component_opportunities
    source = read("../RAILS/gates/lib/source/stimulus_components.rb")
    assert_includes source, "COMPONENT_OPPORTUNITIES"
    assert_includes source, "@stimulus-components/"
    assert_includes source, "severity: :soft"
  end

  def test_existing_custom_controller_is_not_allowed_to_claim_component_ownership
    source = read("../RAILS/gates/lib/source/stimulus_components.rb")
    assert_includes source, "custom Stimulus behavior overlaps"
    assert_includes source, "use the upstream controller when its contract fits"
  end

  def test_shared_boot_remains_the_single_registration_path
    source = read("../RAILS/shared/frontend/stimulus_boot.js")
    assert_includes source, "COMPONENT_REGISTRATIONS"
  end
end
