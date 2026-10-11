# frozen_string_literal: true

require_relative "focus_order_probe"
require_relative "locale_probe"

module Deploy
  # Probes that act on a surface after its geometry walk. Order matters: Tab
  # needs the keys the walk stored on the elements, and the locale probe
  # navigates away and back, which discards them. Each probe is optional
  # evidence, so one that breaks costs its own answer and never the surface.
  module SurfaceProbes
    module_function

    def attach(cdp, surface, payload)
      return payload unless payload.is_a?(Hash) && !payload["error"]

      guarded(payload, "focus") { |p| p.merge(FocusOrderProbe.probe(cdp)) }
        .then { |p| guarded(p, "locale") { |q| LocaleProbe.attach(cdp, surface, q) } }
    end

    def guarded(payload, name)
      yield payload
    rescue StandardError => e
      warn "surface_probes: #{name} probe failed (#{e.class.name.split("::").last}) — #{e.message[0, 80]}"
      payload.merge("#{name}_probe_error" => e.class.name)
    end
  end
end
