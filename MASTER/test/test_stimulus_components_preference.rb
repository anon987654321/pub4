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

  def test_catalog_covers_current_upstream_components
    source = read("../RAILS/gates/lib/source/stimulus_components.rb")
    %w[animated-number carousel chartjs color-picker confirmation dialog dropdown
       glow hotkey lightbox places-autocomplete prefetch remote-rails reveal-controller
       scroll-progress scroll-to sortable sound speech-recognition timeago].each do |name|
      assert_includes source, name
    end
  end

  def test_existing_custom_controller_is_not_allowed_to_claim_component_ownership
    source = read("../RAILS/gates/lib/source/stimulus_components.rb")
    assert_includes source, "custom Stimulus behavior overlaps"
    assert_includes source, "inspect this concrete call site before replacing the controller"
  end

  def test_opportunity_requires_a_concrete_view_call_site
    source = read("../RAILS/gates/lib/source/stimulus_components.rb")
    assert_includes source, "view_controller_usages"
    assert_includes source, "data-controller\\s*=\\s*"
    assert_includes source, "call_sites.empty?"
    assert_includes source, "concrete call site"
  end

  def test_shared_boot_remains_the_single_registration_path
    source = read("../RAILS/shared/frontend/stimulus_boot.js")
    assert_includes source, "COMPONENT_REGISTRATIONS"
  end
end
