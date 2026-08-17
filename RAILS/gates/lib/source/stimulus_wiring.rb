# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # Resolves every Stimulus reference in ERB against something that exists.
  #
  # Four dead references shipped and survived a full audit pass because nothing
  # checks this class of wiring: it does not raise, it does not log, the page
  # renders, and the feature is simply absent. `data-controller="pwa-standalone"`
  # named a controller nobody wrote (amber + bsdports layouts);
  # `data-controller="offline-feed"` named a brgen-local file from amber, whose
  # importmap eager-loads only its own directory; `submit->form-submit#lock`
  # named a method that was never added. Each was invisible until someone grepped
  # for it.
  #
  # Two things are checked, and the second is the one that needs care:
  #
  #   1. Every identifier in data-controller resolves to a registration — either
  #      an application.register("name", …) in stimulus_boot.js, a
  #      @stimulus-components entry in its table, or a file in the app's own
  #      controllers/ directory (eagerLoadControllersFrom derives the identifier
  #      from the filename).
  #
  #   2. Every `event->identifier#method` names a method that exists — but only
  #      when the identifier maps to a first-party file we can read. Vendored
  #      components are registered from node_modules-style bundles and are not
  #      introspected; claiming a missing method there would be a guess.
  class StimulusWiringGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    APPS = %w[amber brgen bsdports].freeze

    BOOT = "shared/frontend/stimulus_boot.js"

    # ERB interpolation inside an identifier list means that part of the value is
    # decided at render time; nothing static can resolve it.
    DYNAMIC = /<%.*?%>/m

    # Method definitions in a Stimulus controller body, including `async name()`,
    # `get name()` and private `#name()`. Getting this wrong in the lenient
    # direction (missing a definition) is what turns this gate into noise, so it
    # is deliberately broad about modifiers and strict about nothing else.
    METHOD_DEF = /^\s{2}(?:static\s+)?(?:async\s+)?(?:get\s+|set\s+)?(#?[a-zA-Z_$][\w$]*)\s*\(/

    def self.run
      new.run
    end

    def initialize(root: RAILS_ROOT)
      @rails_root = root
      @boot_text = File.read(File.join(@rails_root, BOOT))
    end

    def run
      result = GateResult.new
      APPS.each { |app| audit_app(app, result) }
      result
    end

    # Identifiers stimulus_boot registers for every app that calls it.
    def shared_identifiers
      @shared_identifiers ||= (
        @boot_text.scan(/application\.register\("([a-z0-9-]+)"/).flatten +
        @boot_text.scan(/^\s*\["([a-z0-9-]+)",/).flatten
      ).uniq
    end

    # eagerLoadControllersFrom("controllers") turns foo_bar_controller.js into
    # the identifier "foo-bar".
    # Engine controllers register too, and both halves of this gate have to know
    # it: an engine view naming an engine controller is correctly wired, and a
    # glob that sees one side but not the other reports it as broken.
    def app_identifiers(app)
      (Dir.glob(File.join(@rails_root, app, "app/javascript/controllers/*_controller.js")) +
       Dir.glob(File.join(@rails_root, app, "engines/*/app/javascript/controllers/*_controller.js")))
        .map { |path| File.basename(path, "_controller.js").tr("_", "-") }
        .reject { |name| name == "application" }
    end

    private

    def audit_app(app, result)
      registered = (shared_identifiers + app_identifiers(app)).uniq
      views(app).each do |path|
        text = File.read(path)
        rel = path.sub("#{@rails_root}/", "")

        identifiers(text).each do |id|
          result.checked!
          next if registered.include?(id)

          result.fail("#{app}: #{rel} names controller #{id.inspect}, which nothing registers")
        end

        actions(text).each do |id, method|
          next unless registered.include?(id)

          source = first_party_source(app, id)
          next unless source

          result.checked!
          next if methods_in(source).include?(method)

          result.fail("#{app}: #{rel} calls #{id}##{method}, absent from #{source.sub("#{@rails_root}/", "")}")
        end

        targets(text).each do |id, target|
          next unless registered.include?(id)

          source = first_party_source(app, id)
          next unless source
          next if inherits_from_vendor?(source)

          result.checked!
          next if targets_in(source).include?(target)

          result.fail("#{app}: #{rel} marks #{id}:#{target} target, absent from static targets in #{source.sub("#{@rails_root}/", "")}")
        end

        values(text).each do |id, value|
          next unless registered.include?(id)

          source = first_party_source(app, id)
          next unless source
          # A controller that extends a vendored base inherits that base's
          # declared values, and the base is a bundle we do not read — same
          # reason this gate does not introspect vendored methods. Claiming a
          # missing value there would be a guess.
          next if inherits_from_vendor?(source)

          result.checked!
          next if values_in(source).include?(value)

          result.fail("#{app}: #{rel} sets #{id}:#{value}, absent from static values in #{source.sub("#{@rails_root}/", "")}")
        end
      end
    end

    # Shared partials render inside every app, so each app's registration set has
    # to satisfy them.
    #
    # Engine views count too. brgen's verticals are mountable engines and their
    # views render inside brgen with brgen's registrations, so a glob that stops
    # at app/views goes blind to them — which is what happened when maps was
    # extracted on 2026-08-12 and checks_ran fell from over 400 to 391. The
    # floor assertion in stimulus_wiring_gate_test is there to catch exactly
    # that, and it did.
    def views(app)
      Dir.glob(File.join(@rails_root, app, "app/views/**/*.erb")) +
        Dir.glob(File.join(@rails_root, app, "engines/*/app/views/**/*.erb")) +
        Dir.glob(File.join(@rails_root, "shared/app/views/**/*.erb"))
    end

    def identifiers(text)
      raw = text.scan(/data-controller="([^"]*)"/).flatten +
            text.scan(/\bcontroller:\s*"([^"]*)"/).flatten
      # ERB has to be removed from the whole group before splitting: an
      # interpolation contains spaces, so splitting first turns
      # `<%= @dynamic %>` into three tokens of which only the first looks
      # dynamic, and `@dynamic` gets reported as a missing controller.
      raw.flat_map { |group| group.gsub(DYNAMIC, " ").split(/\s+/) }
         .reject { |id| id.empty? || id.include?("<") || id.include?(">") }
         .uniq
    end

    def actions(text)
      text.scan(/[a-z0-9:.@_-]+->([a-z0-9-]+)#(#?[a-zA-Z_$][\w$]*)/).uniq
    end

    # data-<identifier>-<name>-value pairs, resolved against the controller's
    # `static values` block.
    #
    # This is the third leg and it shipped broken too. shared/_action_bar's like
    # button wrote data-action-target-gid-value and data-action-kind-value;
    # action_controller declared neither, so Stimulus never read them and the
    # POST reached Shared::ReactionsController with no subject. That controller
    # opens with params.require(:target_gid), which raises ParameterMissing, so
    # the request 400'd, _rollback reverted the optimistic toggle, and the like
    # button simply did not work. Nothing raised anywhere a human would look.
    #
    # Splitting is ambiguous from the markup alone -- data-action-target-gid-value
    # could be identifier "action" + value "targetGid", or identifier
    # "action-target" + value "gid". Only registered identifiers are candidates,
    # longest first so "feed-hotkey" wins over "feed" when both exist.
    #
    # Only values on the controller's own element count. static values govern
    # that element and nothing else; the same attribute on a target is an
    # ordinary dataset read, which is how dating/profiles/show sets
    # data-tabs-hash-value on each tab and tabs_controller reads
    # tab.dataset.tabsHashValue. Scanning the whole file reported that correct
    # wiring as dead, so the check now looks at one tag at a time and requires
    # the tag to carry data-controller naming the identifier.
    def values(text)
      text.scan(/<[^>]*>/m).flat_map { |tag| values_on_tag(tag) }.uniq
    end

    def values_on_tag(tag)
      declared = tag[/data-controller\s*=\s*"([^"]*)"/, 1]
      return [] unless declared

      on_element = declared.split(/\s+/)
      tag.scan(/data-([a-z0-9-]+)-value\s*=/).flatten.uniq.filter_map do |slug|
        id = registered_prefixes.find do |candidate|
          slug.start_with?("#{candidate}-") && on_element.include?(candidate)
        end
        next unless id

        [ id, camelize(slug.delete_prefix("#{id}-")) ]
      end
    end

    # data-<identifier>-target="name". A target the controller does not declare
    # leaves hasFooTarget false and the feature silently absent — the same class
    # as an undeclared value, one attribute over.
    def targets(text)
      pairs = text.scan(/data-([a-z0-9-]+)-target\s*=\s*"([^"<%]+)"/)
      pairs.flat_map do |slug, names|
        id = registered_prefixes.find { |candidate| slug == candidate }
        next [] unless id

        names.split(/\s+/).reject(&:empty?).map { |name| [ id, name ] }
      end.uniq
    end

    def targets_in(path)
      (@targets ||= {})[path] ||= begin
        source = File.read(path)
        block = source[/static\s+targets\s*=\s*\[(.*?)\]/m, 1].to_s
        block.scan(/["']([a-zA-Z_$][\w$]*)["']/).flatten.uniq
      end
    end

    def registered_prefixes
      @registered_prefixes ||= (shared_identifiers + APPS.flat_map { |a| app_identifiers(a) })
                              .uniq.sort_by { |id| -id.length }
    end

    def camelize(slug)
      head, *rest = slug.split("-")
      ([ head ] + rest.map(&:capitalize)).join
    end

    # Declared names inside `static values = { … }`, in either layout:
    #
    #   static values = { key: String, title: String }          # one line
    #   static values = {                                        # or many
    #     url: String,
    #     activeClass: { type: String, default: "active" }
    #   }
    #
    # An earlier version anchored on /\n\s*\}/ and so saw nothing in the
    # single-line form, which made offline-feed's four declared values look
    # absent. Brace-match instead of guessing at the closing line.
    def values_in(path)
      (@values ||= {})[path] ||= begin
        source = File.read(path)
        start = source.index(/static\s+values\s*=\s*\{/)
        if start.nil?
          []
        else
          open = source.index("{", start)
          depth = 0
          close = nil
          source[open..].each_char.with_index do |ch, offset|
            depth += 1 if ch == "{"
            depth -= 1 if ch == "}"
            if depth.zero?
              close = open + offset
              break
            end
          end
          block = close ? source[(open + 1)...close] : ""
          # Top-level keys only: `activeClass: { type: … }` must not contribute
          # "type" and "default" as declared value names.
          depth = 0
          block.scan(/([{}])|([a-zA-Z_$][\w$]*)\s*:/).each_with_object([]) do |(brace, name), keys|
            if brace
              depth += brace == "{" ? 1 : -1
            elsif depth.zero?
              keys << name
            end
          end.uniq
        end
      end
    end

    # `export default class extends Something` where Something came from a bare
    # module specifier (a vendored package), not a relative or pub4/ path.
    def inherits_from_vendor?(path)
      (@vendor_base ||= {})[path] ||= begin
        source = File.read(path)
        base = source[/export\s+default\s+class\s+extends\s+([A-Za-z_$][\w$]*)/, 1]
        if base.nil? || base == "Controller"
          false
        else
          spec = source[/import\s+#{Regexp.escape(base)}\s+from\s+["']([^"']+)["']/, 1]
          spec.nil? || !(spec.start_with?(".") || spec.start_with?("pub4/") || spec.start_with?("controllers/"))
        end
      end
    end

    def first_party_source(app, id)
      file = "#{id.tr("-", "_")}_controller.js"
      [
        File.join(@rails_root, app, "app/javascript/controllers", file),
        File.join(@rails_root, "shared/frontend", file),
      ].find { |path| File.file?(path) }
    end

    def methods_in(path)
      (@methods ||= {})[path] ||= File.read(path).scan(METHOD_DEF).flatten.uniq
    end
  end
end
