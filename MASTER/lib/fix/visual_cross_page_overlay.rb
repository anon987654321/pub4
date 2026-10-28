# frozen_string_literal: true

require "set"
require_relative "visual_cross_page_drift"
require_relative "visual_cross_page_pages"

module Master
  module Fix
    # Layers renders of DIFFERENT pages in one image so structure shared across
    # pages (header, nav, content edge, footer) shows where it drifts. The ghost
    # stack only layers one surface across time; a first run has no history, so
    # this gives the critique something to see at once.
    #
    # Two kinds of overlay, both built from resting captures only:
    #   role     pages of one app + viewport + role (index, show, form, page),
    #            equal low opacity, top-left aligned, same pixel scale.
    #   viewport the same surface at mobile and desktop. Widths differ by design,
    #            so nothing is scaled: the desktop render is clipped to the mobile
    #            frame's width and laid under it, which compares the leftmost
    #            strip a responsive layout collapses into the mobile column.
    #
    # Everything is bounded and ordered by surface id, so a rerun of the same
    # surfaces builds the same overlays.
    class VisualCrossPageOverlay
      MAX_LAYERS = 8
      MAX_ROLE_OVERLAYS = 5
      MAX_PAIR_OVERLAYS = 3
      OPACITY_RANGE = (0.12..0.35).freeze
      PAIR_OPACITY = 0.45
      MAX_HEIGHT_PX = 4000
      ROLE_TOKENS = {
        "index" => "index", "list" => "index", "results" => "index", "feed" => "index",
        "show" => "show", "new" => "form", "edit" => "form", "form" => "form", "in" => "form"
      }.freeze

      # The role a surface label plays: its last word, with a trailing "_2" dropped.
      def self.role_of(label)
        token = label.to_s.sub(/_\d+\z/, "").split("_").last.to_s
        ROLE_TOKENS.fetch(token, "page")
      end

      # Overlays already built, once each, from captures that share them.
      def self.collect(captures)
        Array(captures).flat_map { |c| Array(c.dig(:visual_evidence, :cross_page)) }.uniq { |o| o[:key] }
      end

      def initialize(dir:)
        @dir = dir
      end

      # Builds every overlay and attaches the ones a capture belongs to as
      # capture[:visual_evidence][:cross_page]. A failed render keeps its drift
      # numbers and loses only the picture.
      def capture(captures, cdp:)
        resting = Array(captures).select { |c| resting?(c) && c[:screenshot] }.sort_by { |c| c[:surface].id }
        overlays = (role_groups(resting).first(MAX_ROLE_OVERLAYS) + pair_groups(resting).first(MAX_PAIR_OVERLAYS))
        overlays.map { |group| build(group, cdp:) }.each do |overlay|
          overlay[:members].each do |id|
            owner = resting.find { |c| c[:surface].id == id }
            ((owner[:visual_evidence] ||= {})[:cross_page] ||= []) << overlay
          end
        end
      end

      private

      def resting?(capture) = capture.dig(:payload, "composition", "state").to_s.then { |s| s.empty? || s == "resting" }

      def parts(capture) = capture[:surface].id.split("/")

      def role_groups(resting)
        grouped = resting.group_by { |c| app, label, viewport = parts(c); [app, viewport, self.class.role_of(label)] }
        grouped.sort.filter_map do |(app, viewport, role), members|
          next if members.size < 2

          { kind: :role, key: "role__#{slug([app, viewport, role].join("__"))}",
            label: "#{app} #{viewport} #{role} pages", captures: members.first(MAX_LAYERS) }
        end
      end

      def pair_groups(resting)
        grouped = resting.group_by { |c| parts(c).first(2) }
        grouped.sort.filter_map do |(app, label), members|
          mobile = members.find { |c| parts(c).last == "mobile" }
          desktop = members.find { |c| parts(c).last == "desktop" }
          next unless mobile && desktop

          { kind: :viewport, key: "viewport__#{slug("#{app}__#{label}")}",
            label: "#{app}/#{label} mobile over desktop", captures: [desktop, mobile] }
        end
      end

      def build(group, cdp:)
        members = group[:captures]
        overlay = { key: group[:key], kind: group[:kind], label: group[:label],
                    members: members.map { |c| c[:surface].id }, layers: members.size, screenshot: nil }
        if group[:kind] == :role
          overlay[:drift] = VisualCrossPageDrift.rows(members.to_h { |c| [c[:surface].id, c[:payload]] })
          overlay[:text] = VisualCrossPageDrift.line(group[:label], overlay[:drift])
          page = role_page(group, members)
        else
          overlay[:drift] = []
          overlay[:text], page = pair_text_and_page(group, members)
        end
        overlay[:screenshot] = render(group[:key], page, cdp:)
        overlay
      rescue StandardError => e
        overlay.merge(error: "#{e.class}: #{e.message}")
      end

      def role_page(group, members)
        opacity = (1.0 / members.size).clamp(OPACITY_RANGE.min, OPACITY_RANGE.max).round(3)
        layers = members.map { |c| layer(c, opacity) }
        VisualCrossPagePages.overlay(
          title: "cross-page overlay · #{group[:label]}",
          note: "#{members.size} pages at #{opacity} opacity, top-left aligned, 1:1 pixels. A sharp edge is shared structure; a double edge or smear is chrome that moved between pages.",
          layers:, width: layers.map { |l| l[:w] }.max, height: [layers.map { |l| l[:h] }.max, MAX_HEIGHT_PX].min
        )
      end

      def pair_text_and_page(group, members)
        desktop, mobile = members
        mw, mh = dimensions(mobile[:screenshot])
        dw, dh = dimensions(desktop[:screenshot])
        layers = [layer(desktop, PAIR_OPACITY), layer(mobile, PAIR_OPACITY)]
        text = "#{group[:label]}: desktop #{dw}x#{dh} clipped to its left #{mw}px under mobile #{mw}x#{mh}; not scaled"
        page = VisualCrossPagePages.overlay(
          title: "viewport overlay · #{group[:label]}",
          note: "Desktop clipped to the mobile frame's width, not scaled, under mobile. Content the desktop shows there but mobile moved or dropped appears as a ghost.",
          layers:, width: mw, height: [[mh, dh].max, MAX_HEIGHT_PX].min
        )
        [text, page]
      end

      def layer(capture, opacity)
        w, h = dimensions(capture[:screenshot])
        { id: capture[:surface].id, path: capture[:screenshot], opacity:, w:, h:,
          boxes: VisualCrossPageDrift.boxes(capture[:payload] || {}) }
      end

      def render(key, page, cdp:)
        html = File.join(@dir, "cross-page-#{key}.html")
        png = File.join(@dir, "cross-page-#{key}.png")
        File.write(html, page)
        cdp.viewport(1800, 1400, mobile: false)
        cdp.navigate("file://#{html}")
        cdp.screenshot(png, capture_beyond_viewport: true)
        png
      end

      def dimensions(path)
        bytes = File.binread(path, 24)
        raise "not a PNG: #{path}" unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)

        [bytes.byteslice(16, 4).unpack1("N"), bytes.byteslice(20, 4).unpack1("N")]
      end

      def slug(value) = value.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")
    end
  end
end
