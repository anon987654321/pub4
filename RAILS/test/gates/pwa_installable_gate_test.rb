# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "gate_probe_harness"
require_relative "../../gates/lib/source/pwa_installable"

# pwa_installable is one of the two gates in this batch that needs nothing but the
# checkout, so its third state is that it has none: no browser, no listening app,
# no deploy stamp, and therefore nothing it can silently decline to measure. The
# last test holds that, because the cheap way to add a live half later is to add
# one that skips — and a manifest gate that skips is a manifest gate that passes.
#
# The trap it encodes is the icon lookup. An icon in a manifest is a path, and it
# resolves from the app's own public/ or from the shared engine's, which mounts
# its own ActionDispatch::Static. A hand check that read one of them reported two
# apps as shipping two of five icons; both were fine. The fixture below plants an
# icon in the shared root only, so a gate that stops reading it fails here.
class PwaInstallableGateTest < Minitest::Test
  include GateProbe

  GATE = Deploy::PwaInstallable

  MANIFEST = <<~JSON
    {
      "name": "<%= city_name %>",
      "short_name": "brgen",
      "start_url": "/",
      "display": "standalone",
      "icons": [
        { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
        { "src": "/icon-512.png", "sizes": "512x512", "purpose": "any" },
        { "src": "/icon-mask.png", "sizes": "512x512", "purpose": "maskable" }
      ]
    }
  JSON

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  # Deliberately asymmetric: the 192 lives in the app's public root and the 512
  # only in the engine's, which is the arrangement that fooled the hand check.
  def plant(root, manifest: MANIFEST)
    GATE::APPS.each do |app|
      write(File.join(root, app, "app/views/pwa/manifest.json.erb"), manifest)
      write(File.join(root, app, "app/views/pwa/service-worker.js"), "self.addEventListener")
      write(File.join(root, app, "public/icon-192.png"), "png")
    end
    write(File.join(root, "shared/public/icon-512.png"), "png")
    write(File.join(root, "shared/public/icon-mask.png"), "png")
  end

  def with_tree(manifest: MANIFEST)
    Dir.mktmpdir("pwa-installable") do |root|
      plant(root, manifest: manifest)
      with_const(GATE, :ROOT, root) { yield root }
    end
  end

  def test_a_manifest_whose_icons_resolve_across_both_public_roots_passes
    with_tree do
      result = GATE.run

      assert_equal :passed, result.outcome, result.failures.join(" | ")
      assert_empty result.unchecked
    end
  end

  def test_an_icon_in_neither_public_root_is_named_with_both_places_it_was_missed
    with_tree do |root|
      FileUtils.rm(File.join(root, "shared/public/icon-512.png"))

      assert_match(%r{brgen declares /icon-512\.png, which is in neither brgen/public nor shared/public},
                   GATE.run.failures.join(" | "))
    end
  end

  # A manifest of nothing but maskable icons installs nowhere, and the sizes
  # check is the only thing that reads purpose. An absent purpose is "any" per
  # spec — bsdports omits it on exactly the two icons that make it installable —
  # so this plants the opposite case and expects the gate to still refuse.
  def test_a_manifest_with_only_maskable_icons_at_a_required_size_is_named
    maskable = MANIFEST.sub('"sizes": "192x192", "type": "image/png"',
                            '"sizes": "192x192", "purpose": "maskable"')
    with_tree(manifest: maskable) do
      assert_match(/declares no 192x192 icon with purpose any/, GATE.run.failures.join(" | "))
    end
  end

  def test_a_manifest_missing_a_required_key_is_named
    with_tree(manifest: MANIFEST.sub(%("start_url": "/",\n  ), "")) do
      assert_match(/declares no start_url — not installable/, GATE.run.failures.join(" | "))
    end
  end

  def test_an_app_with_no_service_worker_is_named
    with_tree do |root|
      FileUtils.rm(File.join(root, "amber/app/views/pwa/service-worker.js"))

      assert_match(%r{amber has no service worker}, GATE.run.failures.join(" | "))
    end
  end

  # BRGEN-115. The same page is served as Bergen and as Oslo, so a literal name is
  # visible at install time on the wrong city.
  def test_a_brgen_manifest_that_hardcodes_a_city_name_is_named
    with_tree(manifest: MANIFEST.sub("<%= city_name %>", "Bergen")) do
      failures = GATE.run.failures.join(" | ")

      assert_match(/does not derive its name from city_name/, failures)
    end
  end

  def test_it_has_no_precondition_it_can_decline_to_measure
    source = File.read(File.join(GATE::ROOT, "gates/lib/source/pwa_installable.rb"))

    refute_match(/inconclusive!|skipped_live|CdpSession|port_open\?/, source,
                 "a live half added here needs a third state, or a skipped manifest check reads as a pass")
  end
end
