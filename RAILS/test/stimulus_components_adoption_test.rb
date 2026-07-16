# frozen_string_literal: true

require "minitest/autorun"

class StimulusComponentsAdoptionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_gate_script_exists
    assert File.file?(File.join(ROOT, "stimulus_components_adoption_gate.rb"))
  end

  def test_boot_registers_password_visibility_and_nested_form
    boot = File.read(File.join(ROOT, "shared/frontend/stimulus_boot.js"))
    %w[password-visibility nested-form carousel].each do |name|
      assert_includes boot, %("#{name}")
    end
  end

  def test_shared_vendor_has_core_packages
    vendor = File.join(ROOT, "shared/vendor/javascript")
    %w[password-visibility rails-nested-form carousel character-counter textarea-autogrow].each do |pkg|
      path = File.join(vendor, "@stimulus-components--#{pkg}.js")
      assert File.file?(path), "missing #{path}"
      assert_operator File.size(path), :>, 100
    end
  end
end