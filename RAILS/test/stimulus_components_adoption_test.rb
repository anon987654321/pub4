# frozen_string_literal: true

require "minitest/autorun"

class StimulusComponentsAdoptionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def check
    require_relative "../../MASTER/checks/lib/source/stimulus_components"
    Deploy::StimulusComponentsCheck
  end

  def test_check_is_registered
    require "yaml"
    row = YAML.safe_load_file(File.expand_path("../../MASTER/checks/checks.yml", __dir__)).fetch("stimulus_components")
    assert_equal "Deploy::StimulusComponentsCheck", row.fetch("class")
    assert File.file?(File.expand_path("../../MASTER/checks/lib/source/stimulus_components.rb", __dir__))
  end

  def test_full_catalogue_is_pinned_and_vendored
    baseline = File.read(File.join(ROOT, "__shared/config/importmap_baseline.rb"))
    pinned = check.pinned_components(baseline)

    check::COMPONENT_PACKAGES.each do |name, package|
      pinned_ok = package.start_with?("@stimulus-components/") ? pinned.include?(name) : baseline.include?(%(pin "#{package}"))
      assert pinned_ok, "missing importmap pin for #{package}"

      filename = check::VENDOR_FILES.fetch(name, "@stimulus-components--#{name}.js")
      path = File.join(ROOT, "__shared/vendor/javascript", filename)
      assert File.file?(path), "missing #{path}"
      assert_operator File.size(path), :>, 100
    end
  end

  def test_full_catalogue_is_registered_from_shared_boot
    boot = File.read(File.join(ROOT, "__shared/frontend/stimulus_boot.js"))
    check::REQUIRED_CONTROLLERS.each do |name|
      assert_match(/\[\s*"#{Regexp.escape(name)}",/, boot, "shared boot does not register #{name}")
    end
  end
end
