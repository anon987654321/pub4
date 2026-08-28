# frozen_string_literal: true

require "minitest/autorun"

class DeviceAwarenessTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHARED = File.join(ROOT, "shared")

  CONTROLLERS = {
    "battery_aware" => %w[connect disconnect],
    "network_aware" => %w[connect disconnect],
    "haptics" => %w[tick success match warning play],
    "geolocation" => %w[connect disconnect prompt pin alertArrival],
    "viewport_aware" => %w[connect disconnect schedule apply],
  }.freeze

  def test_importmap_pins_the_four_controllers
    baseline = File.read(File.join(SHARED, "config/importmap_baseline.rb"))
    CONTROLLERS.each_key do |name|
      assert_includes baseline, %(pin "pub4/#{name}"), "missing pin for pub4/#{name}"
      assert_includes baseline, "#{name}_controller.js"
    end
  end

  def test_stimulus_boot_registers_them
    boot = File.read(File.join(SHARED, "frontend/stimulus_boot.js"))
    %w[battery-aware network-aware haptics geolocation viewport-aware].each do |id|
      assert_includes boot, %("#{id}"), "boot must register #{id}"
    end
  end

  def test_controller_files_export_their_public_methods
    CONTROLLERS.each do |name, methods|
      path = File.join(SHARED, "frontend", "#{name}_controller.js")
      assert File.file?(path), "missing #{path}"
      source = File.read(path)
      methods.each do |method|
        assert_match(/^\s{2}#{Regexp.escape(method)}\s*\(/, source, "#{name} missing #{method}()")
      end
    end
  end

  def test_geolocation_still_patches_with_credentials
    source = File.read(File.join(SHARED, "frontend/geolocation_controller.js"))
    assert_includes source, "radiusKm"
    assert_includes source, 'credentials: "same-origin"'
    assert_includes source, "pub4:located"
    assert_includes source, "brgen:located"
  end

  def test_viewport_aware_writes_keyboard_inset_from_visual_viewport
    source = File.read(File.join(SHARED, "frontend/viewport_aware_controller.js"))
    assert_includes source, "visualViewport"
    assert_includes source, "--keyboard-inset"
    refute_match(/navigator\.virtualKeyboard/, source)
  end

  def test_service_worker_stale_while_revalidates_json_and_honours_actions
    worker = File.read(File.join(SHARED, "pwa/service_worker.js"))
    assert_includes worker, "StaleWhileRevalidate"
    assert_includes worker, "path.includes(\".json\")"
    assert_includes worker, "actions: data.actions || []"
    assert_includes worker, 'action === "view"'
  end

  def test_layouts_mount_battery_and_network_awareness
    %w[
      brgen/app/views/layouts/application.html.erb
      amber/app/views/layouts/application.html.erb
      bsdports/app/views/layouts/application.html.erb
    ].each do |rel|
      body = File.read(File.join(ROOT, rel))
      assert_match(/battery-aware/, body, "#{rel} missing battery-aware")
      assert_match(/network-aware/, body, "#{rel} missing network-aware")
      assert_match(/viewport-aware/, body, "#{rel} missing viewport-aware")
    end
  end
end
