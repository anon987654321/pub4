# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class StimulusComponentsGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    # nested-form (amber only) and checkbox-select-all (brgen only) register
    # in their app-scoped boot files rather than stimulus_boot.js, so every
    # app that doesn't mount them never imports the module. The three files
    # together are this gate's "boot" vocabulary.
    BOOT_FILES = %w[stimulus_boot.js stimulus_boot_social.js stimulus_boot_brgen.js stimulus_boot_amber.js]
      .map { |f| File.join(RAILS_ROOT, "shared/frontend", f) }.freeze
    BASELINE = File.join(RAILS_ROOT, "shared/config/importmap_baseline.rb")
    VENDOR = File.join(RAILS_ROOT, "shared/vendor/javascript")

    # Controller names the boot files must register between them, and package
    # names the importmap must pin. These are two different vocabularies and
    # the one list that held both could not pass: it demanded
    # "rails-nested-form" as a registration, but boot imports that package and
    # registers it under the short name "nested-form", so the check missed
    # wiring that was there. It also demanded "dialog", which is vendored
    # nowhere, imported nowhere, and asked for by no view -- vendoring a package
    # nothing consumes is the futurism shape removed at 3415d7ab7, where a pin
    # was fetched eagerly on every page load to register a controller no ERB
    # referenced. Add dialog back here when a view actually asks for it.
    REQUIRED_CONTROLLERS = %w[
      password-visibility nested-form character-counter
      checkbox-select-all read-more textarea-autogrow
    ].freeze

    REQUIRED_PACKAGES = %w[password-visibility rails-nested-form].freeze

    # Current upstream catalogue, verified against stimulus-components.com.
    # This is an inventory for /fix, not a requirement to install everything.
    UPSTREAM_COMPONENTS = %w[
      animated-number auto-submit carousel character-counter chartjs
      checkbox-select-all clipboard color-picker confirmation content-loader
      dialog dropdown glow hotkey lightbox notification password-visibility
      places-autocomplete popover prefetch rails-nested-form read-more
      remote-rails reveal-controller scroll-progress scroll-reveal scroll-to
      sortable sound speech-recognition textarea-autogrow timeago
    ].freeze

    COMPONENT_OPPORTUNITIES = {
      "clipboard" => /navigator\.clipboard|writeText\(/,
      "password-visibility" => /type\s*=\s*["']password|password.*visibility/i,
      "notification" => /classList\.(add|remove).*?(toast|notification|alert)|setTimeout.*?(toast|notification|alert)/i,
      "read-more" => /(?:show|hide|expand|collapse).*?(text|content)|max-height.*?overflow/i,
      "popover" => /getBoundingClientRect\(\)|style\.(top|left|right|bottom)\s*=|position\s*[:=]\s*["']absolute/i,
      "dropdown" => /aria-expanded|aria-haspopup|classList\.(add|remove).*?(open|active|expanded)/i,
      "auto-submit" => /form\.requestSubmit\(\)|form\.submit\(\)|requestSubmit\(/,
      "textarea-autogrow" => /scrollHeight.*?(style\.height|height\s*=)|clientHeight.*?scrollHeight/i,
      "dialog" => /showModal\(\)|<dialog|aria-modal/i,
      "content-loader" => /fetch\(|Turbo\.visit|turbo-frame/i,
      "confirmation" => /confirm\(|data-confirm|confirmation/i,
      "reveal-controller" => /IntersectionObserver|intersection.*reveal/i,
      "scroll-to" => /scrollIntoView\(|window\.scrollTo\(/,
      "scroll-progress" => /scrollY|scrollTop.*scrollHeight/i
    }.freeze

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

    # The baseline pins components two ways: names in a %w[] list handed to
    # sc_pin, and single `pin "@stimulus-components/x", to: ...` lines.
    def self.pinned_components(baseline)
      listed = baseline.scan(/%w\[([^\]]*)\]\s*\.each\s*\{\s*\|\w+\|\s*sc_pin/).flatten.flat_map(&:split)
      single = baseline.scan(%r{pin\s+"@stimulus-components/([\w-]+)"}).flatten
      (listed + single).uniq
    end

    def self.view_controller_usages
      usages = Hash.new { |hash, key| hash[key] = [] }
      Dir.glob(File.join(RAILS_ROOT, "**/*.{erb,html}")).each do |path|
        next if path.include?("/vendor/") || path.include?("/public/assets/") || path.include?("/node_modules/")

        body = File.read(path, encoding: "UTF-8")
        body.to_enum(:scan, /data-controller\s*=\s*["']([^"']+)["']/).each do
          match = Regexp.last_match
          match[1].split(/\s+/).each do |controller|
            next if controller.empty?
            line = body[0, match.begin(0)].count("\n") + 1
            location = "#{path.sub(ROOT + '/', '')}:#{line}"
            usages[controller] << location unless usages[controller].include?(location)
          end
        end
      end
      usages
    end

    def self.run
      result = GateResult.new
      result.checked!
      missing_inventory = COMPONENT_OPPORTUNITIES.keys.reject { |name| UPSTREAM_COMPONENTS.include?(name) }
      missing_inventory.each { |name| result.fail("Stimulus Components opportunity #{name} is absent from upstream inventory") }

      missing_boot = BOOT_FILES.reject { |f| File.file?(f) }
      if missing_boot.any?
        missing_boot.each { |f| result.fail("missing #{f.sub(ROOT + '/', '')}") }
      else
        boot = BOOT_FILES.map { |f| File.read(f) }.join("\n")
        result.checked!(REQUIRED_CONTROLLERS.size + 1)
        REQUIRED_CONTROLLERS.each do |name|
          result.fail("pub4_stimulus_boot must register #{name}") unless boot.include?(%("#{name}"))
        end
        result.fail("deprecated stimulus_components.js must not return") if File.file?(File.join(RAILS_ROOT, "shared/frontend/stimulus_components.js"))
      end

      if File.file?(BASELINE)
        baseline = File.read(BASELINE)
        result.checked!(1 + (REQUIRED_PACKAGES.size * 2))
        # Vendored means every @stimulus-components pin resolves to a file in
        # shared/vendor/javascript, not that the baseline mentions the path.
        pinned = pinned_components(baseline)
        result.fail("importmap pins no @stimulus-components at all") if pinned.empty?
        pinned.reject { |pkg| File.file?(File.join(VENDOR, "@stimulus-components--#{pkg}.js")) }.each do |pkg|
          result.fail("importmap pins @stimulus-components/#{pkg} with no vendored file in shared/vendor/javascript")
        end
        REQUIRED_PACKAGES.each do |pkg|
          result.fail("importmap missing #{pkg}") unless baseline.include?(pkg)
          # A pin resolves at boot, so a pinned name with no file on disk fails
          # in the browser and nowhere else.
          result.fail("vendored package missing on disk: #{pkg}") unless File.file?(File.join(VENDOR, "@stimulus-components--#{pkg}.js"))
        end
      else
        result.fail("missing shared importmap baseline")
      end

      controller_paths = Dir.glob(File.join(RAILS_ROOT, "**/*_controller.js")).reject { |path| path.include?("/vendor/") }
      view_usages = view_controller_usages
      COMPONENT_OPPORTUNITIES.each do |component, pattern|
        controller_paths.each do |path|
          body = File.read(path)
          next unless body.match?(pattern)
          next if body.match?(%r{@stimulus-components[\/]#{Regexp.escape(component)}})

          controller_name = File.basename(path, "_controller.js").tr("_", "-")
          call_sites = view_usages.fetch(controller_name, [])
          # Source-only similarity is not enough. A custom controller must have
          # a concrete rendered call site before /fix suggests replacing it.
          next if call_sites.empty?

          result.checked!
          call_sites.first(3).each do |call_site|
            result.fail(
              "#{path.sub(ROOT + '/', '')}: custom Stimulus behavior overlaps @stimulus-components/#{component} at #{call_site}; inspect this concrete call site before replacing the controller",
              severity: :soft
            )
          end
        end
      end

      Dir.glob(File.join(RAILS_ROOT, "**", "*.{erb,html}"), File::FNM_DOTMATCH).each do |path|
        next if path.include?("/vendor/")
        next if path.include?("/public/assets/")
        next if path.include?("/node_modules/")

        result.checked!
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
