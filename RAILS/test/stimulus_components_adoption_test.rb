# frozen_string_literal: true

require "minitest/autorun"

class StimulusComponentsAdoptionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def gate
    require_relative "../../MASTER/gates/lib/source/stimulus_components"
    Deploy::StimulusComponentsGate
  end

  def test_gate_is_registered
    require "yaml"
    row = YAML.safe_load_file(File.join(ROOT, "gates/gates.yml")).fetch("stimulus_components")
    assert_equal "Deploy::StimulusComponentsGate", row.fetch("class")
    assert File.file?(File.join(ROOT, "gates/lib/source/stimulus_components.rb"))
  end

  def test_full_catalogue_is_pinned_and_vendored
    baseline = File.read(File.join(ROOT, "shared/config/importmap_baseline.rb"))
    pinned = gate.pinned_components(baseline)

    gate::COMPONENT_PACKAGES.each do |name, package|
      pinned_ok = package.start_with?("@stimulus-components/") ? pinned.include?(name) : baseline.include?(%(pin "#{package}"))
      assert pinned_ok, "missing importmap pin for #{package}"

      filename = gate::VENDOR_FILES.fetch(name, "@stimulus-components--#{name}.js")
      path = File.join(ROOT, "shared/vendor/javascript", filename)
      assert File.file?(path), "missing #{path}"
      assert_operator File.size(path), :>, 100
    end
  end

  def test_full_catalogue_is_registered_from_shared_boot
    boot = File.read(File.join(ROOT, "shared/frontend/stimulus_boot.js"))
    gate::REQUIRED_CONTROLLERS.each do |name|
      assert_match(/\[\s*"#{Regexp.escape(name)}",/, boot, "shared boot does not register #{name}")
    end
  end
end
