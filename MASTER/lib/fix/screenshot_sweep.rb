# frozen_string_literal: true

require "cgi"
require "erb"
require "fileutils"
require "json"
require "time"
require_relative "screenshot_sweep/plan"
require_relative "screenshot_sweep/camera"
require_relative "screenshot_sweep/review_set"
require_relative "visual_runtime"
require_relative "../../checks/support/deploy_inventory"

module Master
  module Fix
    # Every page of every served app, at every declared sweep width, plus the
    # dialogs and sheets its controls open, kept on disk with an index. It
    # judges nothing: VisualPass reviews; this is the record of what rendered.
    #
    # Runs as the screenshot_sweep stage of the visual and all /fix lanes, and
    # alone through `bin/operator visual sweep`. MASTER_SCREENSHOT_SWEEP=0 opts out.
    class ScreenshotSweep
      GEOMETRY = File.join("MASTER", "checks", "data", "geometry_surfaces.yml")
      MAX_PAGES = Integer(ENV.fetch("MASTER_SCREENSHOT_SWEEP_MAX_PAGES", "600"))
      # A JSON or text route the manifest lists is skipped, not failed.
      NOT_A_PAGE = "skipped: not an HTML page"

      Row = Data.define(:app, :host, :path, :route, :status, :shots, :dialogs, :note) do
        def skipped? = note == NOT_A_PAGE
        def failed? = !note.nil? && !skipped?

        def verdict
          return "FAILED #{note}" if failed?

          skipped? ? note : "#{shots.size} widths, #{dialogs.size} dialogs"
        end
      end
      # What one app's pages share while they are captured.
      Visit = Data.define(:camera, :port, :frontier, :dialogs) do
        # Captures the surface and feeds its links back into the crawl.
        def shoot(surface, page_dir:)
          camera.take(surface, page_dir:, dialogs:).tap { |shot| frontier.learn(shot.links) }
        end
      end

      attr_reader :dir

      def initialize(root:, bus: nil, runtime: nil, out: nil)
        @root = root
        @bus = bus
        @runtime = runtime || VisualRuntime.new(root:, bus:)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        # Only a sweep into the standing folder refreshes the review set and
        # prunes; one pointed elsewhere (a test, a one-off) leaves both alone.
        @standing = out.nil?
        @dir = out || File.join(root, "MASTER", ".master", "visual_artifacts", "sweep-#{stamp}")
        @plan = Plan.new(root:)
        @widths = Array(YAML.safe_load_file(File.join(root, GEOMETRY)).fetch("sweep_widths")).map(&:to_i)
      end

      def run(apps: nil, dialogs: true)
        apps = Array(apps).empty? ? Deploy::Inventory.new(root: @root).app_names : Array(apps)
        boot = @runtime.ensure_running!(apps)
        return finish(apps:, rows: [], unresolved: {}, error: "apps not running: #{boot.message}") unless boot.ok?

        rows = []
        unresolved = {}
        Deploy::GeometryProbe.with_browser(root: @root, warm: []) do |cdp|
          camera = Camera.new(cdp:, widths: @widths, dir: @dir)
          apps.each { |app| unresolved[app] = sweep_app(app, camera:, rows:, dialogs:) }
        end
        finish(apps:, rows:, unresolved:)
      ensure
        @runtime.stop_owned!
      end

      private

      # Appends one Row per visited page; returns the routes nothing reached.
      def sweep_app(app, camera:, rows:, dialogs:)
        port = Deploy::GeometryProbe.app_ports(root: @root)[app]
        visit = Visit.new(camera:, port:, frontier: Frontier.new(@plan, app), dialogs:)
        MAX_PAGES.times do
          page = visit.frontier.next_page or break
          rows << capture(page, visit).tap { |row| progress(rows.size + 1, row) }
        end
        visit.frontier.unresolved
      end

      def capture(page, visit)
        page_dir = File.join(@dir, page.app, slugify(page.key))
        shot = visit.shoot(surface_for(page, port: visit.port), page_dir:)
        Row.new(**page.to_h, status: shot.status, shots: shot.widths, dialogs: shot.dialogs,
                             note: shot.html ? nil : NOT_A_PAGE)
      rescue StandardError => e
        failed(page, "#{e.class.name.split("::").last}: #{e.message}")
      end

      # One line per page as it lands, so a long sweep is watchable and a failure shows at once.
      def progress(count, row)
        warn("shots0: #{count} #{row.app} #{row.host}#{row.path} HTTP #{row.status || "?"} #{row.verdict}")
      end

      def failed(page, note) = Row.new(**page.to_h, status: nil, shots: {}, dialogs: [], note:)

      def surface_for(page, port:)
        width = Camera::DIALOG_WIDTH
        Deploy::GeometryProbe::Surface.new(
          app: page.app, label: slugify(page.key), host: page.host, path: page.path, viewport: "w#{width}",
          width:, height: Camera.height(width), snapshot: false, pixel_snapshot: false, port:
        )
      end

      def finish(apps:, rows:, unresolved:, error: nil)
        FileUtils.mkdir_p(@dir)
        summary = totals(rows).merge(
          "generated_at" => Time.now.utc.iso8601, "apps" => apps, "widths" => @widths, "error" => error,
          "unresolved" => unresolved, "rows" => rows.map(&:to_h)
        )
        File.write(File.join(@dir, "index.json"), JSON.pretty_generate(summary))
        File.write(File.join(@dir, "index.html"), Gallery.new(summary).render)
        FileUtils.cp(Gallery::STYLESHEET, File.join(@dir, "gallery.css"))
        refresh_review_set(rows) if @standing && error.nil?
        @bus&.publish("fix_loop:screenshot_sweep", dir: @dir, **totals(rows).transform_keys(&:to_sym))
        summary
      end

      def refresh_review_set(rows)
        review = ReviewSet.new(root: @root, sweep_dir: @dir)
        copied = review.publish!(rows)
        warn("shots0: review set RAILS/screenshot_*.png, #{copied} pages; pruned #{review.prune!} old sweeps")
      end

      def totals(rows)
        {
          "pages" => rows.size,
          "screenshots" => rows.sum { |row| row.shots.size },
          "dialogs" => rows.sum { |row| row.dialogs.size },
          "failed" => rows.count(&:failed?),
          "skipped" => rows.count(&:skipped?)
        }
      end

      def slugify(text)
        slug = text.to_s.gsub(/[^A-Za-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
        slug.empty? ? "root" : slug
      end

      # One static page over the index: per app, per page, every width and
      # every captured dialog. It loads nothing from the network; the markup
      # is screenshot_sweep/gallery.html.erb.
      class Gallery
        TEMPLATE = ERB.new(File.read(File.join(__dir__, "screenshot_sweep", "gallery.html.erb")), trim_mode: "<>")
        STYLESHEET = File.join(__dir__, "screenshot_sweep", "gallery.css")

        attr_reader :summary

        def initialize(summary)
          @summary = summary
        end

        def render = TEMPLATE.result(binding)

        def rows = Array(summary["rows"])

        def unresolved = Hash(summary["unresolved"]).reject { |_app, routes| Array(routes).empty? }

        # [file, caption] pairs: widths first, then the dialogs.
        def figures(row)
          widths = row.fetch(:shots).map { |width, file| [file, "#{width}px"] }
          widths + row.fetch(:dialogs).map { |file| [file, File.basename(file, ".png")] }
        end

        def escape(value) = CGI.escapeHTML(value.to_s)
      end
    end
  end
end
