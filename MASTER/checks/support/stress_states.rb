# frozen_string_literal: true

require "json"
require_relative "cdp_session"
require_relative "stress_measure"

module Deploy
  # Each surface re-rendered under conditions a designer's sample data never
  # meets: German-length compound words, 200% zoom, a 320px screen, a list of
  # nothing / one / two hundred, a phone on its side, reduced motion and dark.
  # The page is measured by StressMeasure and only what the resting page did
  # not already show is a finding.
  #
  # MASTER_VISUAL_STRESS=0 turns it off; MASTER_VISUAL_STRESS_STATES caps the
  # states per surface per pass (rotating with the pass, so a long run covers
  # them all).
  module StressStates
    COMPOUNDS = %w[
      Rettsmedisinaldokumentasjonsforvaltningen Kommunikasjonsutviklingsavdelingsleder
      Sykehusinnkjøpssamarbeidsorganisasjonen Arbeidsmiljøverneombudsrepresentant
      Skattebetalerforeningsmedlemsregisteret Eiendomsmeglerforetaksregistreringen
    ].freeze

    ORDER = %i[compound narrow320 zoom200 list_200 list_empty list_one landscape reduced_motion dark].freeze
    LIST_COUNTS = { list_200: 200, list_empty: 0, list_one: 1 }.freeze
    TALL_PAGE_PX = 8000
    SETTLE = 0.2

    # Surface-shaped copy for a state: same app and path, a label that names it.
    State = Struct.new(:name, :width, :height, :mobile, :media, keyword_init: true)

    module_function

    def enabled? = ENV.fetch("MASTER_VISUAL_STRESS", "1") != "0"
    def limit = Integer(ENV.fetch("MASTER_VISUAL_STRESS_STATES", "4"))

    # The states this surface can show, in priority order, given what the
    # resting page offers (a list to resize, a stylesheet that answers dark).
    def plan(surface, scan)
      support = scan["support"] || {}

      ORDER.select do |name|
        case name
        when :narrow320 then surface.width.to_i > 320
        when :landscape then surface.width.to_i < 500
        when :list_200, :list_one then scan["list"].to_h["count"].to_i.positive?
        when :list_empty then !scan["list"].nil?
        when :reduced_motion then support["reduced_motion"]
        when :dark then support["dark"]
        else true
        end
      end
    end

    def pick(names, pass:, count: limit)
      return [] if names.empty? || count <= 0

      names.rotate(((pass.to_i - 1) * count) % names.length).first(count)
    end

    def geometry_of(name, surface)
      w = surface.width.to_i
      h = surface.height.to_i
      mobile = w < 500

      case name
      when :narrow320 then State.new(name:, width: 320, height: h, mobile: true)
      when :zoom200 then State.new(name:, width: [w / 2, 200].max, height: [h / 2, 300].max, mobile:)
      when :landscape then State.new(name:, width: h, height: w, mobile: true)
      when :reduced_motion then State.new(name:, width: w, height: h, mobile:, media: { "prefers-reduced-motion" => "reduce" })
      when :dark then State.new(name:, width: w, height: h, mobile:, media: { "prefers-color-scheme" => "dark" })
      else State.new(name:, width: w, height: h, mobile:)
      end
    end

    # The full set of captures for one surface, or [] when disabled or the page
    # cannot be scanned. Always leaves the session at the surface's own viewport.
    def capture(cdp, surface, dir:, pass:, count: limit)
      enabled? ? capture_all(cdp, surface, dir:, pass:, count:) : []
    end

    def capture_all(cdp, surface, dir:, pass:, count:)
      scan = scan(cdp, surface)
      return [] unless scan

      pick(plan(surface, scan), pass:, count:).filter_map { |name| run_state(cdp, surface, name, scan, dir:) }
    rescue CdpSession::Error => e
      warn "stress_states: #{surface.id} abandoned (#{e.class.name.split("::").last}) — #{e.message[0, 80]}"
      []
    ensure
      restore(cdp, surface)
    end

    # The resting page once: list container, what the stylesheet supports, and
    # the baseline findings every state is compared against.
    def scan(cdp, surface)
      load(cdp, surface, geometry_of(:resting, surface))
      { "list" => cdp.evaluate(StressScripts::LIST_DETECT_JS), "support" => cdp.evaluate(StressScripts::SUPPORT_JS),
        "baseline" => cdp.evaluate(StressMeasure::MEASURE_JS) }
    end

    def load(cdp, surface, state)
      cdp.viewport(state.width, state.height, mobile: state.mobile)
      features = (state.media || {}).map { |name, value| { name:, value: } }
      cdp.command("Emulation.setEmulatedMedia", features:)
      cdp.navigate(surface.url)
    end

    def restore(cdp, surface)
      cdp.command("Emulation.setEmulatedMedia", features: [])
      cdp.viewport(surface.width, surface.height, mobile: surface.width.to_i < 500)
    rescue CdpSession::Error
      nil
    end

    def run_state(cdp, surface, name, scan, dir:)
      state = geometry_of(name, surface)
      load(cdp, surface, state)
      applied = mutate(cdp, name, scan)
      return if applied == :unavailable

      sleep SETTLE
      measured = cdp.evaluate(StressMeasure::MEASURE_JS)
      record(cdp, surface, state, measured, scan, applied, dir:)
    rescue CdpSession::Error => e
      warn "stress_states: #{surface.id} #{name} failed (#{e.class.name.split("::").last})"
      nil
    end

    def mutate(cdp, name, _scan)
      if name == :compound
        script = StressScripts::COMPOUND_JS.sub("__WORDS__") { COMPOUNDS.to_json }.sub("__LIMIT__", "8")
        return cdp.evaluate(script) || :unavailable
      end
      return {} unless LIST_COUNTS.key?(name)
      return :unavailable unless cdp.evaluate(StressScripts::LIST_DETECT_JS)

      cdp.evaluate(StressScripts::LIST_SET_JS.sub("__COUNT__", LIST_COUNTS.fetch(name).to_s)) || :unavailable
    end

    def record(cdp, surface, state, measured, scan, applied, dir:)
      derived = derived_surface(surface, state)
      findings = StressMeasure.new_findings(measured, scan["baseline"])

      payload = {
        "elements" => [], "scroll_width" => measured["scroll_width"], "client_width" => measured["viewport_width"],
        "composition" => { "state" => "stress", "stress" => state.name.to_s, "base_surface" => surface.id,
                           "trigger" => "#{state.name} #{state.width}x#{state.height}" },
        "stress" => { "name" => state.name.to_s, "findings" => findings, "applied" => applied,
                      "list" => scan["list"], "viewport" => [state.width, state.height] }
      }

      shot = File.join(dir, "#{derived.id.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")}.png")
      cdp.screenshot(shot, capture_beyond_viewport: measured["scroll_height"].to_i <= TALL_PAGE_PX)
      { surface: derived, payload:, screenshot: shot, journeys: [], platform: {} }
    end

    def derived_surface(surface, state)
      GeometryProbe::Surface.new(
        app: surface.app, label: "#{surface.label}__stress_#{state.name}", host: surface.host, path: surface.path,
        viewport: surface.viewport, width: state.width, height: state.height, snapshot: false,
        port: surface.port, profile: surface.profile
      )
    end
  end
end
