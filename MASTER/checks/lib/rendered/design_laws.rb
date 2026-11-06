# frozen_string_literal: true

require_relative "../../../lib/gap"
require_relative "../../support/check_result"
require_relative "../../support/geometry_probe"
require_relative "../../support/rendered_design/capture"

module Deploy
  # The design-book Laws' rendered half on every declared surface, phones first: one snapshot
  # per page (390, 360, 320, then 1280) judged by each Law's evaluator in RenderedDesign, the
  # same code the Laws prove their fixtures with. Findings are soft and name their Law.
  class DesignLawsCheck
    LIMIT = Integer(ENV.fetch("MASTER_DESIGN_LAW_SURFACES", "6"))
    MOTION_MS = Integer(ENV.fetch("MASTER_DESIGN_LAW_MOTION_MS", "6000"))

    def self.run = new.result

    def result
      CheckResult.new.tap { |result| measure(result) }
    rescue CdpSession::Unavailable, CdpSession::Error, SystemCallError => e
      CheckResult.new.tap { |failed| failed.inconclusive!("design_laws: Chrome/CDP stopped (#{e.message})") }
    end

    private

    def measure(result)
      unless GeometryProbe.available?
        return result.inconclusive!("design_laws: no Chrome - design Laws not rendered", gap: Master::Gap::NO_BROWSER)
      end

      pages = GeometryProbe.reachable(GeometryProbe.surfaces).uniq(&:url).first(LIMIT)
      return result.inconclusive!("design_laws: no declared surface is reachable") if pages.empty?

      GeometryProbe.with_browser(warm: pages) do |cdp|
        pages.each do |surface|
          plan = RenderedDesign::Capture::Plan.full(motion_ms: MOTION_MS, route: surface.path)
          judge(result, surface:, snap: RenderedDesign::Capture.snapshot(cdp, surface.url, plan))
        end
      end
    end

    def judge(result, surface:, snap:)
      result.checked!(RenderedDesign.ids.size)
      RenderedDesign.ids.each do |id|
        RenderedDesign.judge(id, snap).first(4).each do |message|
          result.fail("design_laws: #{surface.app}/#{surface.label} #{message} law=#{id}", severity: :soft)
        end
      end
    end
  end
end
