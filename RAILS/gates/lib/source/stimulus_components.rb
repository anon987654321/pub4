# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class StimulusComponentsGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    BOOT = File.join(RAILS_ROOT, "shared/frontend/stimulus_boot.js")
    BASELINE = File.join(RAILS_ROOT, "shared/config/importmap_baseline.rb")
    VENDOR = File.join(RAILS_ROOT, "shared/vendor/javascript")

    # Controller names stimulus_boot.js must register, and package names the
    # importmap must pin. These are two different vocabularies and the one list
    # that held both could not pass: it demanded "rails-nested-form" as a
    # registration, but boot imports that package and registers it under the
    # short name "nested-form" (stimulus_boot.js:17, :66), so the check missed
    # wiring that was there. It also demanded "dialog", which is vendored
    # nowhere, imported nowhere, and asked for by no view -- vendoring a package
    # nothing consumes is the futurism shape removed at 3415d7ab7, where a pin
    # was fetched eagerly on every page load to register a controller no ERB
    # referenced. Add dialog back here when a view actually asks for it.
    REQUIRED_CONTROLLERS = %w[
      password-visibility nested-form carousel character-counter
      checkbox-select-all read-more textarea-autogrow
    ].freeze

    REQUIRED_PACKAGES = %w[password-visibility rails-nested-form carousel].freeze

    FORBIDDEN_VIEW_PATTERNS = [
      /data-controller="char-counter"/,
      /controller:\s*["']char-counter/,
      /char-counter-max-value/,
      /data-char-counter-target/
    ].freeze

    FORBIDDEN_CONTROLLER_FILES = %w[
      char_counter_controller.js
      textarea_autogrow_controller.js
      stimulus_rails_nested_form_controller.js
    ].freeze

    def self.run
      result = GateResult.new

      unless File.file?(BOOT)
        result.fail("missing stimulus_boot.js")
      else
        boot = File.read(BOOT)
        REQUIRED_CONTROLLERS.each do |name|
          result.fail("pub4_stimulus_boot must register #{name}") unless boot.include?(%("#{name}"))
        end
        result.fail("deprecated stimulus_components.js must not return") if File.file?(File.join(RAILS_ROOT, "shared/frontend/stimulus_components.js"))
      end

      if File.file?(BASELINE)
        baseline = File.read(BASELINE)
        result.fail("importmap must pin shared vendor stimulus-components") unless baseline.include?("vendor/javascript")
        REQUIRED_PACKAGES.each do |pkg|
          result.fail("importmap missing #{pkg}") unless baseline.include?(pkg)
          # A pin resolves at boot, so a pinned name with no file on disk fails
          # in the browser and nowhere else.
          result.fail("vendored package missing on disk: #{pkg}") unless File.file?(File.join(VENDOR, "@stimulus-components--#{pkg}.js"))
        end
      else
        result.fail("missing shared importmap baseline")
      end

      Dir.glob(File.join(RAILS_ROOT, "**", "*.{erb,html}"), File::FNM_DOTMATCH).each do |path|
        next if path.include?("/vendor/")
        next if path.include?("/public/assets/")
        next if path.include?("/node_modules/")

        body = File.read(path)
        FORBIDDEN_VIEW_PATTERNS.each do |pattern|
          result.fail("#{path.sub(ROOT + '/', '')}: forbidden legacy char-counter pattern") if body.match?(pattern)
        end
      end

      Dir.glob(File.join(RAILS_ROOT, "**/app/javascript/controllers/*.js")).each do |path|
        base = File.basename(path)
        result.fail("remove duplicate controller #{path.sub(ROOT + '/', '')}") if FORBIDDEN_CONTROLLER_FILES.include?(base)
      end

      Dir.glob(File.join(VENDOR, "@stimulus-components--*.js")).each do |path|
        result.fail("empty vendor package #{path}") if File.size(path) < 100
      end

      result
    end
  end
end
