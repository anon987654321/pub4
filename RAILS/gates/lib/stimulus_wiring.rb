# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"

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
    ROOT = File.expand_path("../../..", __dir__)
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
    def app_identifiers(app)
      Dir.glob(File.join(@rails_root, app, "app/javascript/controllers/*_controller.js"))
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
      end
    end

    # Shared partials render inside every app, so each app's registration set has
    # to satisfy them.
    def views(app)
      Dir.glob(File.join(@rails_root, app, "app/views/**/*.erb")) +
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
