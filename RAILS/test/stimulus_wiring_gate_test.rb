# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "yaml"
require_relative "../gates/lib/source/stimulus_wiring"

class StimulusWiringGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_manifest_registers_the_gate_under_layout_suite
    row = YAML.safe_load_file(File.join(ROOT, "gates/gates.yml")).fetch("stimulus_wiring")

    assert_equal "lib/source/stimulus_wiring", row.fetch("require")
    assert_equal "Deploy::StimulusWiringGate", row.fetch("class")
    assert_equal "layout_suite", row.fetch("covered_by")
  end

  def test_layout_suite_runs_the_gate
    source = File.read(File.join(ROOT, "gates/lib/layout_suite.rb"))
    assert_includes source, "stimulus_wiring"
    assert_includes source, "StimulusWiringGate"
  end

  def test_family_wiring_resolves
    result = Deploy::StimulusWiringGate.run

    assert_empty result.failures, "dead Stimulus references:\n  #{result.failures.join("\n  ")}"
    assert_operator result.checks_ran, :>, 400, "gate measured almost nothing — check the view glob"
  end

  # A gate that cannot fail is not a gate. These two are the exact shapes that
  # shipped: an identifier nobody registers, and an action method nobody wrote.
  def test_reports_an_unregistered_identifier
    failures = with_probe(%(<div data-controller="totally-absent"></div>))

    assert_equal 1, failures.size, failures.inspect
    assert_includes failures.first, "totally-absent"
  end

  def test_reports_an_unregistered_engine_helper_controller
    failures = with_file("brgen/engines/maps/app/helpers/stimulus_wiring_probe_helper.rb",
                         %(tag.div(data: { controller: "totally-absent-engine-helper" }))) do
      Deploy::StimulusWiringGate.run.failures.select { |f| f.include?("stimulus_wiring_probe_helper") }
    end

    assert_equal 1, failures.size, failures.inspect
    assert_includes failures.first, "totally-absent-engine-helper"
  end

  def test_reports_an_unregistered_helper_controller
    failures = with_helper_probe(%(tag.div(data: { controller: "totally-absent-helper" })))

    assert_equal 1, failures.size, failures.inspect
    assert_includes failures.first, "totally-absent-helper"
  ensure
    FileUtils.rm_f(File.join(ROOT, "amber/app/helpers/stimulus_wiring_probe_helper.rb"))
  end

  # A shared helper's controller binds the apps whose views call the helper:
  # brgen calls lazy_image_tag, amber does not, and a method nobody calls or
  # cannot be named binds every app.
  def test_a_shared_helper_binds_the_apps_that_call_it
    gate = Deploy::StimulusWiringGate.new
    path = File.join(ROOT, "shared/app/helpers/shared/probe_helper.rb")
    called = %(def lazy_image_tag(source)\n  tag.img(data: { controller: "lazy-image" })\nend\n)
    unnamed = %(tag.img(data: { controller: "lazy-image" })\n)

    refute gate.send(:shared_helper_unused_by?, "brgen", path, called, "lazy-image")
    assert gate.send(:shared_helper_unused_by?, "amber", path, called, "lazy-image")
    refute gate.send(:shared_helper_unused_by?, "amber", path, unnamed, "lazy-image")
    refute gate.send(:shared_helper_unused_by?, "amber", File.join(ROOT, "amber/app/helpers/x.rb"), called, "lazy-image")
  end

  def test_reports_a_missing_engine_action_method
    with_file("brgen/engines/playlist/app/javascript/controllers/stimulus_mount_probe_controller.js",
              %(import { Controller } from "@hotwired/stimulus"
export default class extends Controller {}
)) do
      failures = with_file("brgen/engines/playlist/app/views/stimulus_wiring_probe.html.erb",
                           %(<button data-action="click->stimulus-mount-probe#noSuchMethod">x</button>)) do
        Deploy::StimulusWiringGate.run.failures.select { |f| f.include?("stimulus_mount_probe") }
      end

      assert_equal 1, failures.size, failures.inspect
      assert_includes failures.first, "stimulus-mount-probe#noSuchMethod"
    end
  end

  def test_reports_a_missing_action_method
    failures = with_probe(%(<button data-action="click->luxury-product#noSuchMethod">x</button>))

    assert_equal 1, failures.size, failures.inspect
    assert_includes failures.first, "luxury-product#noSuchMethod"
  end

  def test_ignores_erb_interpolated_identifiers
    assert_empty with_probe(%(<div data-controller="<%= @dynamic %>"></div>))
  end

  # Vendored @stimulus-components controllers have no first-party source to read,
  # so an action against one must not be guessed at.
  def test_does_not_guess_at_vendored_component_methods
    assert_empty with_probe(%(<div data-controller="lightbox" data-action="click->lightbox#whatever"></div>))
  end

  # The third leg: a data-*-value the controller never declares. This is the
  # exact shape that shipped in shared/_action_bar — the like button wrote
  # data-action-target-gid-value and data-action-kind-value, action_controller
  # declared neither, so the POST reached Shared::ReactionsController with no
  # subject, params.require(:target_gid) raised ParameterMissing, and the
  # optimistic toggle silently rolled back on the 400.
  def test_reports_a_value_nobody_declares
    failures = with_probe(%(<button data-controller="action" data-action-no-such-value="x">y</button>))

    assert_equal 1, failures.size, failures.inspect
    assert_includes failures.first, "action:noSuch"
  end

  # The fourth leg: a data-*-target the controller never declares. Stimulus leaves
  # hasFooTarget false and the feature is simply absent — the same silence as an
  # undeclared value, one attribute over.
  def test_reports_a_target_nobody_declares
    failures = with_probe(%(<div data-controller="scroll-chrome" data-scroll-chrome-target="nosuch"></div>))

    assert_equal 1, failures.size, failures.inspect
    assert_includes failures.first, "scroll-chrome:nosuch"
  end

  def test_accepts_declared_targets
    assert_empty with_probe(%(<div data-controller="scroll-chrome" data-scroll-chrome-target="peel"></div>))
  end

  # …and it must not fire on values that are declared, in either brace layout.
  def test_accepts_declared_values_written_on_one_line
    # offline_feed_controller declares `static values = { key, title, url, meta }`
    # on a single line. Anchoring the block scan on a newline made all four look
    # absent.
    assert_empty with_probe(%(<article data-controller="offline-feed" data-offline-feed-key-value="k" data-offline-feed-title-value="t"></article>))
  end

  # A controller extending a vendored base inherits that base's values, and the
  # base is a bundle this gate does not read — same rule it already applies to
  # vendored methods.
  def test_does_not_guess_at_values_inherited_from_a_vendored_base
    assert_empty with_probe(%(<div data-controller="character-counter" data-character-counter-countdown-value="true"></div>))
  end

  # The reverse leg: a controller registered and mounted by nothing.
  def test_reports_a_registered_controller_nothing_mounts
    failures = with_controller_probe { mount_failures }

    assert_equal 1, failures.size, failures.inspect
    assert_includes failures.first, %(amber: controller "stimulus-mount-probe")
  end

  def test_a_view_a_tag_helper_or_a_script_mounts_a_controller
    [
      ["amber/app/views/items/_stimulus_mount_probe.html.erb", %(<div data-controller="toast stimulus-mount-probe"></div>)],
      ["amber/app/helpers/stimulus_mount_probe_helper.rb", %(tag.div(data: { controller: "stimulus-mount-probe" }))],
      ["amber/app/javascript/stimulus_mount_probe.js", %(el.setAttribute("data-controller", "stimulus-mount-probe"))],
    ].each do |path, text|
      failures = with_controller_probe { with_file(path, text) { mount_failures } }

      assert_empty failures, "#{path}: #{failures.inspect}"
    end
  end

  # Another app's element does not load an app-local controller.
  def test_a_mount_in_another_app_does_not_count
    failures = with_controller_probe do
      with_file("bsdports/app/views/ports/_stimulus_mount_probe.html.erb", %(<div data-controller="stimulus-mount-probe"></div>)) { mount_failures }
    end

    assert_includes failures, %(amber: controller "stimulus-mount-probe" is registered and no view, helper or script mounts it)
  end

  def test_an_exemption_fails_once_its_controller_is_mounted_or_gone
    gate = Deploy::StimulusWiringGate.new(unmounted_allowed: { "scroll-chrome" => "planted", "never-registered" => "planted" })
    failures = gate.run.failures

    assert failures.any? { |f| f.include?(%(names "scroll-chrome", which is mounted now)) }, failures.inspect
    assert failures.any? { |f| f.include?(%(names "never-registered", which nothing registers)) }, failures.inspect
  end

  # An app controller named after a shared registration is never loaded, so the
  # element it was written for runs the shared component instead. clipboard is
  # in stimulus_boot.js, the file every app imports, so it shadows in all
  # three — dropdown lives in stimulus_boot_brgen.js now (brgen only), so it
  # no longer shadows a same-named controller bsdports writes for itself.
  def test_reports_an_app_controller_a_shared_registration_shadows
    failures = with_file("bsdports/app/javascript/controllers/clipboard_controller.js",
                         %(import { Controller } from "@hotwired/stimulus"\nexport default class extends Controller {}\n)) do
      Deploy::StimulusWiringGate.run.failures.select { |f| f.include?("never loads") }
    end

    assert_equal [%(bsdports: controller "clipboard" never loads — a shared boot file registers that identifier first)], failures
  end

  def test_a_shadow_exemption_fails_once_nothing_is_shadowed
    failures = Deploy::StimulusWiringGate.new(shadowed_allowed: { "lightbox" => "planted", "toast" => "planted" }).run.failures

    assert failures.any? { |f| f.include?(%(SHADOWED_ALLOWED names "toast")) }, failures.inspect
  end

  private

  def mount_failures
    Deploy::StimulusWiringGate.run.failures.select { |f| f.include?("stimulus-mount-probe") }
  end

  def with_controller_probe(&)
    with_file("amber/app/javascript/controllers/stimulus_mount_probe_controller.js",
              %(import { Controller } from "@hotwired/stimulus"\nexport default class extends Controller {}\n), &)
  end

  def with_file(relative, text)
    path = File.join(ROOT, relative)
    File.write(path, text)
    yield
  ensure
    FileUtils.rm_f(path)
  end

  # The gate reads the real tree; a probe file is the only way to exercise the
  # failure paths without a second fixture copy of three Rails apps.
  def with_helper_probe(source)
    path = File.join(ROOT, "amber/app/helpers/stimulus_wiring_probe_helper.rb")
    File.write(path, "module StimulusWiringProbeHelper\n  def stimulus_wiring_probe\n    #{source}\n  end\nend\n")
    Deploy::StimulusWiringGate.run.failures.select { |f| f.include?("stimulus_wiring_probe_helper") }
  ensure
    FileUtils.rm_f(path)
  end

  def with_probe(markup)
    path = File.join(ROOT, "amber/app/views/items/_stimulus_wiring_probe.html.erb")
    File.write(path, markup)
    Deploy::StimulusWiringGate.run.failures.select { |f| f.include?("_stimulus_wiring_probe") }
  ensure
    FileUtils.rm_f(path)
  end
end
