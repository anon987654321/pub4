# frozen_string_literal: true

require_relative "contracts"
require Shared::Contracts.tool_path("importmap_preload_audit")

module Shared
  # The importmap contract, shared because the importmap is shared: all three
  # apps eval shared/config/importmap_baseline.rb, so a pin that puts a CDN on
  # the critical path does it to all three at once. One copy of the assertions,
  # three one-line test files.
  #
  #   class ImportmapExternalHostsTest < ActiveSupport::TestCase
  #     include Shared::ImportmapExternalHostsExamples
  #   end
  #
  # It has to boot Rails rather than read importmap_baseline.rb as text, and
  # that is the whole reason it exists. Two external hosts were preloaded on
  # every brgen.no page and we pinned only one: cable_ready ships its own
  # config/importmap.rb pinning morphdom to ga.jspm.io, gem paths are drawn
  # before the app's, and `pin` defaults to preload: true. Nothing in this repo
  # named the host. A source scan cannot see a dependency's pins; the resolved
  # importmap has it in one line.
  module ImportmapExternalHostsExamples
    def self.included(base)
      base.class_eval do
        # Guards the guard. Both external-host assertions pass vacuously against
        # an importmap that resolved to nothing, which is what a boot-order
        # mistake looks like.
        test("the importmap resolves to something") { assert_importmap_resolves }
        test("no pin emits an external modulepreload") { assert_no_external_preload }
        test("every local pin resolves to a file the asset pipeline serves") { assert_local_pins_resolve }
        test("every external pin is one we chose on purpose") { assert_external_pins_chosen }
      end
    end

    def assert_importmap_resolves
      assert_operator resolved_imports.size, :>=, 40,
                      "importmap resolved #{resolved_imports.size} pins - the check, not the tree"
    end

    def assert_no_external_preload
      external = Operator::ImportmapPreloadAudit.external_preloads(app_importmap, resolver: importmap_resolver)

      assert_empty external, <<~MSG.strip
        these pins put a third-party host in <link rel="modulepreload"> on every page:

          #{external.map { |name, url| "#{name} -> #{url}" }.join("\n  ")}

        `pin` defaults to preload: true, so the browser fetches these before
        first paint whether or not anything imports them. Either vendor the
        module into shared/vendor/javascript, or pin it preload: false and
        import it lazily. If the pin comes from a gem rather than from
        importmap_baseline.rb, re-pinning the same name after the gem paths
        are drawn overrides it.
      MSG
    end

    # A pin whose file is gone still lands in the importmap, and the browser
    # finds out with a 404 on the first page that imports it. Resolved through
    # the asset load path, so a gem's file counts as much as one in
    # shared/frontend or shared/vendor/javascript.
    def assert_local_pins_resolve
      local = app_importmap.packages.values.reject { |package| package.path.start_with?("http") }
      missing = local.reject { |package| Rails.application.assets.load_path.find(package.path) }

      refute_empty local
      assert_empty missing.map { |package| "#{package.name} -> #{package.path}" },
                   "these pins point at no file in the asset load path"
    end

    def assert_external_pins_chosen
      unexpected = Operator::ImportmapPreloadAudit.unexpected_external_pins(app_importmap, resolver: importmap_resolver)

      assert_empty unexpected, <<~MSG.strip
        these pins resolve to a third-party host and are not on the allowlist:

          #{unexpected.map { |name, url| "#{name} -> #{url}" }.join("\n  ")}

        Lazy or not, each is a runtime dependency on someone else's uptime
        and a record of every visitor's IP handed to them. Vendor it, or add
        it to Operator::ImportmapPreloadAudit::ALLOWED_EXTERNAL_PINS along with
        the reason it is acceptable.
      MSG
    end

    def app_importmap = Rails.application.importmap
    def importmap_resolver = ApplicationController.helpers
    def resolved_imports = JSON.parse(app_importmap.to_json(resolver: importmap_resolver)).fetch("imports", {})
  end
end
