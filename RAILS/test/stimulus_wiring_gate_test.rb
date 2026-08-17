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
    assert_empty with_probe(%(<div data-controller="carousel" data-action="click->carousel#whatever"></div>))
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

  private

  # The gate reads the real tree; a probe file is the only way to exercise the
  # failure paths without a second fixture copy of three Rails apps.
  def with_probe(markup)
    path = File.join(ROOT, "amber/app/views/items/_stimulus_wiring_probe.html.erb")
    File.write(path, markup)
    Deploy::StimulusWiringGate.run.failures.select { |f| f.include?("_stimulus_wiring_probe") }
  ensure
    FileUtils.rm_f(path)
  end
end
