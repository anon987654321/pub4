# frozen_string_literal: true

require "minitest/autorun"

class StimulusComponentsAdoptionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_gate_is_registered
    require "yaml"
    row = YAML.safe_load_file(File.join(ROOT, "gates/gates.yml")).fetch("stimulus_components")

    assert_equal "Deploy::StimulusComponentsGate", row.fetch("class")
    assert File.file?(File.join(ROOT, "gates/lib/source/stimulus_components.rb"))
  end

  def test_boot_registers_password_visibility_and_nested_form
    # password-visibility is universal; nested-form is amber-only — only
    # amber's views mount it (RailsNestedForm), so it registers in
    # stimulus_boot_amber.js rather than the file every app imports.
    boot = File.read(File.join(ROOT, "shared/frontend/stimulus_boot.js"))
    assert_includes boot, %("password-visibility")

    amber_boot = File.read(File.join(ROOT, "shared/frontend/stimulus_boot_amber.js"))
    assert_includes amber_boot, %("nested-form")
  end

  def test_shared_vendor_has_core_packages
    vendor = File.join(ROOT, "shared/vendor/javascript")
    %w[password-visibility rails-nested-form character-counter textarea-autogrow].each do |pkg|
      path = File.join(vendor, "@stimulus-components--#{pkg}.js")
      assert File.file?(path), "missing #{path}"
      assert_operator File.size(path), :>, 100
    end
  end

  # The gate proves pins are vendored by resolving each one, so it has to see
  # both spellings the baseline uses.
  def test_the_gate_reads_listed_and_single_pins
    require_relative "../../MASTER/gates/lib/source/stimulus_components"
    baseline = %(%w[\n  clipboard dropdown\n].each { |name| sc_pin.call(name) }\n) +
               %(pin "@stimulus-components/textarea-autogrow", to: "x.js"\npin "sortablejs"\n)

    assert_equal %w[clipboard dropdown textarea-autogrow], Deploy::StimulusComponentsGate.pinned_components(baseline)
  end
end
