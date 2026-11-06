# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../../../lib/gap"
require_relative "../../support/check_result"
require_relative "../../support/geometry_probe"
require_relative "../../support/state_matrix"

module Deploy
  # The declared component states, rendered: geometry_surfaces.yml#state_matrix through
  # Deploy::StateMatrix, one composite image per component and a finding for a focus state no
  # one can see or a component that overflows. Mobile first and bounded per component.
  class StateMatrixCheck
    OUTPUT = File.join(Dir.tmpdir, "pub4-state-matrix")

    def self.run = new.result

    def initialize(config: GeometryProbe.config["state_matrix"] || {})
      @config = config
    end

    def result
      CheckResult.new.tap { |result| measure(result) }
    rescue CdpSession::Unavailable, CdpSession::Error, SystemCallError => e
      CheckResult.new.tap { |failed| failed.inconclusive!("state_matrix: Chrome/CDP stopped (#{e.message})") }
    end

    private

    def measure(result)
      unless GeometryProbe.available?
        return result.inconclusive!("state_matrix: no Chrome - states not rendered", gap: Master::Gap::NO_BROWSER)
      end

      live = components.select { |_row, surface| GeometryProbe.reachable([surface]).any? }
      return result.inconclusive!("state_matrix: no declared component's app is reachable") if live.empty?

      GeometryProbe.with_browser(warm: live.map(&:last)) do |cdp|
        live.each { |row, surface| judge(result, cdp, id: row["id"], target: target(row, surface)) }
      end
    end

    # Each declared component with the first surface it names; the inventory is mobile first.
    def components
      surfaces = GeometryProbe.surfaces
      Array(@config["components"]).filter_map do |row|
        surface = surfaces.find { |candidate| "#{candidate.app}/#{candidate.label}" == row["surface"] }
        [row, surface] if surface
      end
    end

    def target(row, surface) = StateMatrix::Target.new(url: surface.url, selector: row["selector"])

    def judge(result, cdp, id:, target:)
      dir = File.join(OUTPUT, id.tr("/", "-"))
      FileUtils.mkdir_p(dir)
      rows = StateMatrix.capture(cdp, target, cells: StateMatrix.plan(@config), dir:)
      return result.incomplete!("state_matrix: #{id} matched nothing on #{target.url}") if rows.empty?

      result.checked!(rows.size)
      findings = StateMatrix.judge(id, rows, must_differ: Array(@config["must_differ"]))
      findings.each { |line| result.fail(line, severity: :soft) }
      result.warn("state_matrix: #{id} #{rows.size} cell(s) -> #{StateMatrix.composite(rows, out: "#{dir}.png")}")
    end
  end
end
