# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "visual_lane"
require_relative "scale_snap"
require_relative "tap_target_pad"
require_relative "layout_score_render"
require_relative "rails_visual_graph"
require_relative "pass_law"

module Master
  module Fix
    # VisualLane's real collaborators: Reachability's layout sweep, ScaleSnap and
    # TapTargetPad behind a re-render that rebuilds the CSS first, and RepairLoop for a
    # group neither settles. Kept apart from VisualLane so its decisions stay testable.
    class VisualLaneWorld
      SCALE_LAWS = /rhythm|scale|spacing|space|font|radius|type/i
      STYLESHEET = /\.s?css\z/
      SURFACES_PER_GROUP = 3

      BRIEF = <<~TEXT
        RENDERED GROUP REPAIR
        The findings below are one cause, measured by a real browser on the routes and viewports
        they name. Change the one source that causes all of them; do not patch each symptom.
        A route answering 4xx/5xx is a missing record, route or link: fix the link or the lookup,
        never by hiding the error. Change no design token, scale value or law.
      TEXT

      # tools: reachability (the sweep), committer (one commit per kept mechanical fix) and
      # repair_loop, ->(brief) { a RepairLoop briefed for one group }.
      def initialize(repo_root:, tools:, bus: nil)
        @repo_root = repo_root
        @reachability, @committer, @repair_loop = tools.values_at(:reachability, :committer, :repair_loop)
        @bus = bus

        @evidence = SweepEvidence.new(bus:)
        @rerender = Rerender.new(repo_root:)
        @sources = Sources.new(repo_root:, rerender: @rerender)
      end

      def world
        VisualLane::World.new(
          sweep: -> { @evidence.read(@reachability.layout_sweep || @reachability.observe_layout_suite!) },
          resweep: -> { @evidence.read(@reachability.observe_layout_suite!) },
          snap: method(:snap), pad: method(:pad), repair: method(:repair)
        )
      end

      def snap(group)
        path = @sources.resolve(group.file)
        return unless group.law.match?(SCALE_LAWS) && path&.match?(STYLESHEET)

        findings = ScaleSnap.propose(root: @repo_root, files: [path])
        return :nothing_off_scale if findings.empty?

        rescore = @rerender.hook(group.surfaces, path) or return :no_surface_to_measure
        outcome = ScaleSnap.apply(findings, root: @repo_root, rescore:)
        committed(group, path:, outcome: outcome[:applied].to_i.positive? ? :applied : outcome.keys.first)
      end

      def pad(group)
        return unless TapTargetPad.applicable?(group)

        path = @sources.styled(group.selector).first or return :no_stylesheet_styles_it
        rescore = @rerender.hook(group.surfaces, path)
        outcome = TapTargetPad.apply(path, group.selector, root: @repo_root, rescore:)
        committed(group, path:, outcome:)
      end

      def repair(group)
        sources = @sources.for(group)
        return :no_source_file if sources.empty?

        result = @repair_loop.call(BRIEF).run_once([sources.first], external_violations: [violation(group, sources)])
        result[:fixed].to_i.positive? ? :applied : result.fetch(:status, :not_kept)
      end

      private

      def violation(group, sources)
        {
          law: VisualPass::LAW_ID, file: sources.first, line: 1, severity: group.runtime? ? :error : :warning,
          message: "#{group.law}: #{group.member_count} finding(s), one cause (#{group.key})\n#{group.evidence}",
          fix: "Also read: #{sources.drop(1).first(5).map { |path| path.delete_prefix("#{@repo_root}/") }.join(", ")}"
        }
      end

      def committed(group, path:, outcome:)
        return outcome unless outcome == :applied

        @committer.commit_if_dirty("fix_loop: visual lane #{group.law} [#{group.id}]", owned_paths: [path])
        outcome
      end

      # Where a group's cause lives: the file the finding named, then the stylesheets that
      # style its selector, then the route's controller and views for a page that broke.
      class Sources
        def initialize(repo_root:, rerender:)
          @repo_root = repo_root
          @rerender = rerender
        end

        def for(group)
          file, selector, surfaces = group.to_h.values_at(:file, :selector, :surfaces)
          named = [resolve(file)].compact
          styles = selector ? styled(selector) : []
          routed = group.runtime? ? @rerender.declared(surfaces).flat_map { |surface| graph.sources_for(surface) } : []
          (named + styles + routed.reject { |path| path.include?("/layouts/") }).uniq.first(8)
        end

        def styled(selector) = TapTargetPad.stylesheets_for(selector, ScaleSnap.stylesheets(@repo_root))

        def resolve(file)
          return if file.to_s.empty?

          candidates = [file, File.join("RAILS", file)].map { |rel| File.expand_path(rel, @repo_root) }
          found = candidates.find { |path| File.file?(path) }
          found || ScaleSnap.stylesheets(@repo_root).find { |path| path.end_with?("/#{file}") }
        end

        private

        def graph = (@graph ||= RailsVisualGraph.new(root: @repo_root).build)
      end

      # The re-render a mechanical fix is kept on: rebuild the CSS the edit can reach, then no
      # measured surface may score lower than before it.
      class Rerender
        def initialize(repo_root:) = @repo_root = repo_root

        # nil when no declared surface shows the stylesheet, since an unmeasured edit is a guess.
        def hook(surface_ids, path)
          app = path.to_s.delete_prefix("#{@repo_root}/")[%r{\ARAILS/([^/]+)/}, 1].to_s
          surfaces = measured(surface_ids, app)
          return if surfaces.empty?

          apps = app == "__shared" ? surfaces.map(&:app).uniq : [app]
          before = LayoutScoreRender.rescore_hook(surfaces, root: @repo_root)
          ->(changed) { apps.all? { |name| build_css(name) } && before.call(changed) }
        end

        def declared(surface_ids)
          ids = surface_ids.first(SURFACES_PER_GROUP)
          probe.surfaces.select { |surface| ids.include?(surface.id) }
        end

        private

        def measured(surface_ids, app)
          named = declared(surface_ids)
          named.empty? ? probe.surfaces.select { |surface| surface.app == app }.first(SURFACES_PER_GROUP) : named
        end

        def build_css(app)
          require_relative "../operator/design_run"
          Operator::DesignRun.build_css(app, root: @repo_root)
        end

        def probe
          require_relative "../../checks/support/geometry_probe"
          Deploy::GeometryProbe
        end
      end

      # A layout sweep as VisualLane reads it: its findings, and from the browser sweep's
      # evidence manifest the page URL and screenshot of every route/viewport cell.
      class SweepEvidence
        def initialize(bus: nil) = @bus = bus

        def read(result)
          findings = Array(result.failures) + Array(result.soft_failures)
          manifest = manifest_for(result)
          { findings:, manifest:, **cells(manifest) }
        end

        private

        def cells(manifest)
          rows = manifest ? JSON.parse(File.read(manifest)).fetch("results", []) : []
          shot = rows.select { |row| row["screenshot"] }

          { urls: rows.to_h { |row| [surface_id(row), row["url"]] },
            screenshots: shot.to_h { |row| [surface_id(row), row["screenshot"]] } }
        rescue JSON::ParserError, SystemCallError => e
          Master::Ground::Swallow.log(e, context: "visual_lane.manifest", event_bus: @bus)
          {}
        end

        def surface_id(row) = [row["app"], row["surface"], row["viewport"]].join("/")

        # Named in the sweep's warnings when it rendered; otherwise the newest manifest, which a
        # replayed sweep (Deploy::SweepReplay) read its rows from.
        def manifest_for(result)
          named = Array(result.warnings).filter_map { |line| line[/evidence manifest (\S+manifest\.json)/, 1] }.last
          return named if named

          default = File.join(Dir.tmpdir, "pub4-browser-diagnostics")
          base = File.expand_path(ENV.fetch("CHECK_BROWSER_DIAGNOSTICS_OUTPUT", default))
          Dir.glob(File.join(base, "*", "manifest.json")).max_by { |path| File.mtime(path) }
        end
      end
    end
  end
end
