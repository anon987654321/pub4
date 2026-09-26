# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../../MASTER/gates/lib/source/stimulus_components"

# The gate suggests an upstream Stimulus Component only where a custom
# controller duplicates one and a view actually mounts it. These run the gate
# over a fixture tree, so the suggestion is measured rather than its wording.
class TestStimulusComponentsPreference < Minitest::Test
  Gate = Deploy::StimulusComponentsGate
  REPO = File.expand_path("../..", __dir__)
  CLIPBOARD_JS = "export default class { copy() { navigator.clipboard.writeText(this.text) } }\n"

  def test_a_mounted_custom_controller_gets_a_soft_component_suggestion
    soft = soft_failures_for(
      "RAILS/app1/app/javascript/controllers/copy_controller.js" => CLIPBOARD_JS,
      "RAILS/app1/app/views/posts/show.html.erb" => %(<div data-controller="copy"></div>\n),
    )

    hit = soft.find { |message| message.include?("copy_controller.js") }
    refute_nil hit, "a mounted clipboard controller drew no suggestion: #{soft.inspect}"
    assert_includes hit, "@stimulus-components/clipboard"
  end

  def test_catalog_covers_current_upstream_components
    %w[animated-number carousel chartjs color-picker confirmation dialog dropdown
       glow hotkey lightbox places-autocomplete prefetch remote-rails reveal-controller
       scroll-progress scroll-to sortable sound speech-recognition timeago].each do |name|
      assert_includes Gate::UPSTREAM_COMPONENTS, name
    end
    assert_empty Gate::COMPONENT_OPPORTUNITIES.keys - Gate::UPSTREAM_COMPONENTS,
                 "an opportunity names a component the inventory does not have"
  end

  # The suggestion names the overlap and the call site, and tells /fix to look
  # before it replaces anything; a controller already built on the package
  # draws nothing.
  def test_existing_custom_controller_is_not_allowed_to_claim_component_ownership
    soft = soft_failures_for(
      "RAILS/app1/app/javascript/controllers/copy_controller.js" => CLIPBOARD_JS,
      "RAILS/app1/app/javascript/controllers/wrapped_controller.js" =>
        %(import Clipboard from "@stimulus-components/clipboard"\n#{CLIPBOARD_JS}),
      "RAILS/app1/app/views/posts/show.html.erb" =>
        %(<div data-controller="copy"></div>\n<div data-controller="wrapped"></div>\n),
    )

    hit = soft.find { |message| message.include?("copy_controller.js") }
    refute_nil hit
    assert_includes hit, "custom Stimulus behavior overlaps"
    assert_includes hit, "inspect this concrete call site before replacing the controller"
    assert_includes hit, "RAILS/app1/app/views/posts/show.html.erb:1"
    assert soft.none? { |message| message.include?("wrapped_controller.js") },
           "a controller built on the package was told to use the package"
  end

  def test_opportunity_requires_a_concrete_view_call_site
    soft = soft_failures_for(
      "RAILS/app1/app/javascript/controllers/lonely_controller.js" => CLIPBOARD_JS,
      "RAILS/app1/app/views/posts/show.html.erb" => %(<p>no controller here</p>\n),
    )

    assert soft.none? { |message| message.include?("lonely_controller.js") },
           "source similarity alone drew a suggestion: #{soft.inspect}"
  end

  def test_view_controller_usages_reads_every_controller_and_its_line
    with_tree(
      "RAILS/app1/app/views/a.html.erb" => %(<p>\n<div data-controller = "copy toast"></div>\n),
    ) do
      usages = Gate.view_controller_usages
      assert_equal ["RAILS/app1/app/views/a.html.erb:2"], usages["copy"]
      assert_equal ["RAILS/app1/app/views/a.html.erb:2"], usages["toast"]
    end
  end

  # Every @stimulus-components registration goes through the shared boot: the
  # module is executed with its imports stubbed and asked what it registers.
  def test_shared_boot_remains_the_single_registration_path
    names = boot_registrations(File.join(REPO, "RAILS/shared/frontend/stimulus_boot.js"))

    %w[auto-submit clipboard toast read-more reveal textarea-autogrow password-visibility popover].each do |name|
      assert_includes names, name
    end
    assert_equal names.uniq, names, "a controller registered twice"
  end

  private

  def soft_failures_for(files)
    with_tree(files) { Gate.run.soft_failures.map { |failure| failure.is_a?(Hash) ? failure[:message].to_s : failure.to_s } }
  end

  # Points the gate's roots at a throwaway tree for the length of the block.
  def with_tree(files)
    Dir.mktmpdir do |root|
      files.each do |rel, body|
        path = File.join(root, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      rails = File.join(root, "RAILS")
      overrides = {
        ROOT: root, RAILS_ROOT: rails,
        BOOT_FILES: [File.join(rails, "shared/frontend/stimulus_boot.js")],
        BASELINE: File.join(rails, "shared/config/importmap_baseline.rb"),
        VENDOR: File.join(rails, "shared/vendor/javascript")
      }
      saved = overrides.keys.to_h { |name| [name, Gate.const_get(name)] }
      begin
        overrides.each { |name, value| replace_const(name, value) }
        yield
      ensure
        saved.each { |name, value| replace_const(name, value) }
      end
    end
  end

  def replace_const(name, value)
    Gate.send(:remove_const, name)
    Gate.const_set(name, value)
  end

  # Bare specifiers resolve to one stub module, so the boot file runs under
  # node without the importmap and reports each application.register call.
  def boot_registrations(boot)
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      runner = File.join(dir, "run.mjs")
      File.write(runner, <<~JS)
        import { registerHooks } from "node:module"
        import { pathToFileURL } from "node:url"
        const stub = "export default class Stub { static initialize() {} }; export function noteSession() {}"
        registerHooks({
          resolve(specifier, context, next) {
            if (/^(\\.|\\/|file:|node:|data:)/.test(specifier)) return next(specifier, context)
            return { url: "data:text/javascript," + encodeURIComponent(stub), shortCircuit: true }
          },
        })
        const { bootPub4Stimulus } = await import(pathToFileURL(process.argv[2]).href)
        const names = []
        bootPub4Stimulus({ register: (name) => names.push(name) })
        console.log(JSON.stringify(names))
      JS
      out, err, status = Open3.capture3("node", runner, boot)
      assert status.success?, "stimulus_boot.js did not run: #{err}"
      JSON.parse(out)
    end
  end
end
