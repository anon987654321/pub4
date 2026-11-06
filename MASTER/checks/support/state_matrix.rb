# frozen_string_literal: true

require "json"
require_relative "pixel_match"

module Deploy
  # geometry_surfaces.yml#state_matrix, planned, captured and judged. BackstopJS's idea without
  # its runtime: a scenario list of component x state x width x locale x scheme, each cell a
  # cropped screenshot over the CDP session the sweep holds, tiled into one image a component.
  module StateMatrix
    MOBILE_MAX = 767
    PAD = 8
    COLUMNS = 4

    LOCALES = { "nb" => "nb-NO,nb;q=0.9", "en" => "en-US,en;q=0.9" }.freeze
    PSEUDO = { "hover" => %w[hover], "focus-visible" => %w[focus focus-visible], "active" => %w[active] }.freeze
    SCRIPTED = {
      "disabled" => "el.disabled = true; el.setAttribute('aria-disabled', 'true');",
      "loading" => "el.setAttribute('aria-busy', 'true');",
      "error" => "el.setAttribute('aria-invalid', 'true');",
      "empty" => "el.textContent = '';",
      "long-text" => "el.textContent = 'Langtekst for et smalt felt '.repeat(6);",
    }.freeze

    RECT_JS = <<~'JS'
      ((selector) => {
        const el = document.querySelector(selector);
        if (!el) return null;
        el.scrollIntoView({ block: "center" });
        const r = el.getBoundingClientRect();
        return { x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height,
                 overflow: el.scrollWidth > el.clientWidth + 1 || r.right > innerWidth + 1 || r.left < -1 };
      })(__SELECTOR__)
    JS

    # One cell of the matrix, and how a session is put into it.
    Cell = Data.define(:state, :width, :scale, :locale, :scheme) do
      def height = width <= MOBILE_MAX ? 844 : 900

      def label = "#{state} #{width}px#{" x#{scale}" if scale > 1} #{locale} #{scheme}"

      def twin = with(state: "default")

      def emulate(cdp, url)
        cdp.viewport(width, height, mobile: width <= MOBILE_MAX, scale:)
        cdp.command("Emulation.setEmulatedMedia", features: [{ name: "prefers-color-scheme", value: scheme }])
        cdp.headers("Accept-Language" => LOCALES.fetch(locale, locale))
        cdp.navigate(url)
      end
    end

    # The component a row of the matrix declares: where it is and how to find it on the page.
    Target = Data.define(:url, :selector) do
      def apply(cdp, state)
        return cdp.force_pseudo_state(selector, PSEUDO.fetch(state)) if PSEUDO.key?(state)
        return unless SCRIPTED.key?(state)

        cdp.evaluate("((el) => { if (el) { #{SCRIPTED.fetch(state)} } })(document.querySelector(#{selector.to_json}))")
      end

      def release(cdp, state) = PSEUDO.key?(state) && cdp.force_pseudo_state(selector, [])

      def rect(cdp) = cdp.evaluate(RECT_JS.sub("__SELECTOR__") { selector.to_json })
    end

    module_function

    # Mobile first: default and every state at the first width, then the other widths, then the
    # 200% zoom, then the second locale and the dark scheme, cut at cells_per_component.
    def plan(config)
      first, *others = Array(config["widths"]).map(&:to_i)
      base = Cell.new(state: "default", width: first, scale: 1, locale: config["locales"].first,
                      scheme: config["schemes"].first)
      cells = [base, *config["states"].map { |state| base.with(state:) }, *others.map { |width| base.with(width:) }]
      (cells + variants(base, config)).first(cap(config))
    end

    def cap(config) = Integer(ENV.fetch("MASTER_VISUAL_STATE_CELLS", config.fetch("cells_per_component", 12)))

    def variants(base, config)
      zoom = config["zoom"] || {}
      zoomed = zoom["factor"] ? [base.with(width: zoom["width"].to_i / zoom["factor"].to_i, scale: zoom["factor"])] : []
      zoomed + config["locales"].drop(1).map { |locale| base.with(locale:) } +
        config["schemes"].drop(1).map { |scheme| base.with(scheme:) }
    end

    # One row a cell: the cell, the component's box, whether it overflowed and the cropped shot.
    def capture(cdp, target, cells:, dir:)
      cells.each_with_index.filter_map do |cell, index|
        cell.emulate(cdp, target.url)
        target.apply(cdp, cell.state)
        rect = target.rect(cdp) or next
        shot = cdp.screenshot(File.join(dir, format("cell-%02d.png", index)), clip: clip(rect))
        target.release(cdp, cell.state)
        { cell:, rect:, overflow: rect["overflow"], shot: }
      end
    end

    def clip(rect)
      { x: [rect["x"].to_f - PAD, 0].max, y: [rect["y"].to_f - PAD, 0].max,
        width: [rect["w"].to_f + 2 * PAD, 1].max, height: [rect["h"].to_f + 2 * PAD, 1].max }
    end

    # Findings for one component: a must-differ state identical to its default, and overflow.
    def judge(component, rows, must_differ:)
      overflowing = rows.select { |row| row[:overflow] }.map do |row|
        "state_matrix overflow: #{component} #{row[:cell].label} overflows its box or the viewport law=INTRINSIC_LAYOUT"
      end
      unseen(component, rows, must_differ:) + overflowing
    end

    def unseen(component, rows, must_differ:)
      shots = rows.to_h { |row| [row[:cell], row[:shot]] }
      rows.filter_map do |row|
        cell = row[:cell]
        twin = shots[cell.twin]
        next unless must_differ.include?(cell.state) && twin && same?(twin, row[:shot])

        "state_matrix unseen_state: #{component} #{cell.label} renders identically to default law=FOCUS_VISIBLE"
      end
    end

    def same?(one, two)
      compared = PixelMatch.compare(baseline_path: one, current_path: two)
      compared[:status] == :compared && compared[:pixel_diff_count].zero?
    end

    # The cells tiled COLUMNS to a row on white, each in a slot the size of the largest.
    def composite(rows, out:)
      frames = rows.map { |row| PixelMatch.read(row[:shot]) }
      slot = [frames.map(&:width).max, frames.map(&:height).max]
      size = sheet_size(slot, frames.size)
      File.binwrite(out, PngDiff.encode_rgba(*size, sheet(frames, slot:, size:).pack("N*")))
      out
    end

    def sheet_size(slot, count) = [slot[0] * [COLUMNS, count].min, slot[1] * count.fdiv(COLUMNS).ceil]

    def sheet(frames, slot:, size:)
      canvas = Array.new(size[0] * size[1], 0xffffffff)
      frames.each_with_index do |frame, index|
        left, top = origin(index, slot)
        frame.lines.each_with_index { |pixels, line| canvas[(top + line) * size[0] + left, pixels.size] = pixels }
      end
      canvas
    end

    def origin(index, slot) = [(index % COLUMNS) * slot[0], (index / COLUMNS) * slot[1]]
  end
end
