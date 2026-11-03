# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../../../checks/support/composition_probe"

module Master
  module Fix
    class ScreenshotSweep
      # One browser tab's work for a page: load it, read its links, shoot it at
      # each width, then let CompositionProbe open and record its dialogs.
      class Camera
        SETTLE = 0.15
        DIALOG_WIDTH = 390
        # Chrome refuses a capture taller than its texture limit (16384px);
        # such a page is recorded down to this depth and its file says so.
        MAX_CAPTURE_HEIGHT = 16_000

        # Same per-page bound VisualPass uses for composition states.
        DIALOG_LIMIT = Integer(ENV.fetch("MASTER_SCREENSHOT_SWEEP_DIALOGS", "12"))
        LINKS_JS = <<~JS
          JSON.stringify(Array.from(document.querySelectorAll("a[href]")).map(a => {
            try { const u = new URL(a.href, location.href); return [u.host, u.pathname]; } catch (e) { return null; }
          }).filter(Boolean))
        JS

        Shot = Data.define(:status, :html, :links, :widths, :dialogs)

        def initialize(cdp:, widths:, dir:)
          @cdp = cdp
          @widths = widths
          @dir = dir
        end

        def take(surface, page_dir:, dialogs:)
          FileUtils.mkdir_p(page_dir)
          load(surface)
          status = @cdp.status
          return Shot.new(status:, html: false, links: [], widths: {}, dialogs: []) unless html?
          return error_shot(status, page_dir) if status.to_i >= 400

          links = JSON.parse(@cdp.evaluate(LINKS_JS).to_s)
          widths = shoot_widths(page_dir)
          states = dialogs ? capture_dialogs(surface, page_dir) : []
          Shot.new(status:, html: true, links:, widths:, dialogs: states)
        end

        def self.height(width) = width < 768 ? 844 : 900

        private

        def load(surface)
          first = @widths.first
          @cdp.viewport(first, self.class.height(first), mobile: first < 500)
          @cdp.navigate(surface.url)
        end

        def html? = @cdp.evaluate("document.contentType") == "text/html"

        # An error page is recorded as it first shows, viewport-sized: a Rails
        # development routing error lists every route and runs to 600,000px.
        def error_shot(status, page_dir)
          file = File.join(page_dir, "w#{@widths.first}_http#{status}.png")
          @cdp.screenshot(file)
          Shot.new(status:, html: true, links: [], widths: { @widths.first => relative(file) }, dialogs: [])
        end

        def shoot_widths(page_dir)
          @widths.to_h do |width|
            @cdp.viewport(width, self.class.height(width), mobile: width < 500)
            sleep SETTLE
            [width, relative(shoot(page_dir, width))]
          end
        end

        def shoot(page_dir, width)
          file = File.join(page_dir, "w#{width}.png")
          @cdp.screenshot(file, capture_beyond_viewport: true)
        rescue CdpSession::Error => e
          raise unless e.message.include?("too large")

          shoot_top(page_dir, width)
        end

        def shoot_top(page_dir, width)
          file = File.join(page_dir, "w#{width}_top#{MAX_CAPTURE_HEIGHT}px.png")
          clip = { x: 0, y: 0, width:, height: MAX_CAPTURE_HEIGHT }
          @cdp.screenshot(file, capture_beyond_viewport: true, clip:)
        end

        # CompositionProbe clicks each control that changes state and records
        # what opened; the files it writes are the page's dialogs and sheets.
        def capture_dialogs(surface, page_dir)
          before = Dir.glob(File.join(page_dir, "**", "*.png"))
          @cdp.viewport(DIALOG_WIDTH, self.class.height(DIALOG_WIDTH), mobile: true)
          Deploy::CompositionProbe.capture(@cdp, surface, dir: page_dir, pass: 1, limit: DIALOG_LIMIT)
          (Dir.glob(File.join(page_dir, "**", "*.png")) - before).sort.map { |file| relative(file) }
        end

        def relative(file) = file.delete_prefix("#{@dir}/")
      end
    end
  end
end
