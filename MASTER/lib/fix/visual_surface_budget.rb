# frozen_string_literal: true

require_relative "../../gates/support/cdp_session"

module Master
  module Fix
    # One declared surface at a time: say which one is being captured, and give
    # up on it with a precise reason when it outlives MASTER_VISUAL_SURFACE_TIMEOUT_S.
    # The sweep carries on with the next surface; the missing one is reported by
    # the coverage line, and the reason is printed here as it happens.
    module VisualSurfaceBudget
      SECONDS = Integer(ENV.fetch("MASTER_VISUAL_SURFACE_TIMEOUT_S", "120"))

      module_function

      def run(cdp, surface, index, total, seconds: SECONDS, io: $stdout, &block)
        say(io, "capturing #{surface.id} #{index + 1}/#{total} ...")
        cdp.with_budget(seconds, surface.id, &block)
      rescue Deploy::CdpBudget::Exceeded, StandardError => e
        # A probe that raises costs that surface, named and counted as missed,
        # not the other surfaces of the sweep.
        say(io, "FAILED #{surface.id} #{index + 1}/#{total}: #{e.class.name.split("::").last}: #{e.message}")
        nil
      end

      # The ghost-stack evidence render for one capture: a navigation and a
      # screenshot per view, minutes in all on a large sweep, so it reports too.
      def evidence(cdp, capture, index, total, seconds: SECONDS, io: $stdout, &block)
        id = capture.fetch(:surface).id
        say(io, "evidence #{id} #{index + 1}/#{total} ...") if (index % 10).zero?
        cdp.with_budget(seconds, "evidence #{id}", &block)
      rescue Deploy::CdpBudget::Exceeded, StandardError => e
        say(io, "FAILED evidence #{id} #{index + 1}/#{total}: #{e.class.name.split("::").last}: #{e.message}")
        nil
      end

      def say(io, text)
        Master::Trace::Dmesg.status("visual0", text, io:)
      end
    end
  end
end
