# frozen_string_literal: true

require "json"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/geometry_probe"

module Deploy
  # PERF-100. The telemetry existed and the ratchet did not.
  #
  # RAILS/shared/frontend/hotwire.js has sampled LCP, CLS and INP through
  # PerformanceObserver at one percent and beaconed them to /web_vitals for some
  # time, and design_contract_test.rb proves that wiring is present. What none of
  # it does is fail: a one-percent sample lands in a log line nobody reads, so a
  # regression that doubles LCP ships. GATE_ADEQUACY.md records the hole as its
  # own item 8, "no LCP/INP or request waterfall gate".
  #
  # This is that gate. It measures the two paint metrics on a real load rather
  # than trusting the beacon, because a budget checked against production
  # telemetry can only report a regression after it has shipped.
  #
  # INP is deliberately absent from the live half. It is defined over real user
  # interactions and a scripted load produces none; PerformanceObserver reports
  # nothing for it, and a gate that reads that silence as zero would print the
  # best possible score for a page nobody touched. The source half asserts INP
  # is still being collected in the field instead, which is the only honest
  # reading available here.
  class WebVitalsBudget
    ROOT = File.expand_path("../../../..", __dir__)
    SHARED = File.join(ROOT, "RAILS", "shared")
    HOTWIRE = File.join(SHARED, "frontend", "hotwire.js")

    # Google's "good" thresholds, which is the right starting ceiling: this is a
    # ratchet, so the number only ever comes down, and starting under the public
    # definition of good would fail on arrival and be raised once, which is how
    # a ratchet dies.
    LCP_BUDGET_MS = 2500
    CLS_BUDGET = 0.1

    # A load has to settle before layout shift means anything: CLS accumulates
    # over the page's life, and reading it at first paint reports the shift that
    # has not happened yet as zero.
    SETTLE_S = 2.0

    def self.run = new.run

    def run
      @result = GateResult.new
      check_field_collection
      measure_live
      @result
    end

    private

    # The field half. If the sampler stops collecting a metric, the live budget
    # below still passes and the fleet goes blind, so the two halves are checked
    # together.
    def check_field_collection
      unless File.file?(HOTWIRE)
        @result.fail("web_vitals_budget: #{rel(HOTWIRE)} missing — nothing collects vitals in the field")
        return
      end

      source = File.read(HOTWIRE)
      # Deliberately not counted with checked!. This half is the blindness alarm,
      # not the measurement: counting it let the gate print "LCP and CLS within
      # budget" on a machine with no Chrome, having read three strings out of a
      # JavaScript file and measured neither metric. A failure here still blocks,
      # because failures outrank the check count.
      { "largest-contentful-paint" => "LCP", "layout-shift" => "CLS", "first-input" => "INP" }
        .each do |entry_type, metric|
          next if source.include?(entry_type)

          @result.fail("web_vitals_budget: hotwire.js no longer observes #{entry_type} — #{metric} " \
                       "stopped being collected in the field")
        end
    end

    def measure_live
      unless GeometryProbe.available?
        @result.inconclusive!("web_vitals_budget: no Chrome/Chromium — LCP and CLS not measured")
        return
      end

      surfaces = GeometryProbe.surfaces.first(1)
      GeometryProbe.unreachable_apps(surfaces).each do |app|
        @result.skipped_live("web_vitals_budget: #{app} port closed — paint budget not measured")
      end
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("web_vitals_budget: no app reachable — paint budget not measured")
        return
      end

      GeometryProbe.with_browser(warm: live) { |cdp| live.each { |surface| judge(cdp, surface) } }
    rescue StandardError => e
      @result.errored!("web_vitals_budget: #{e.class}: #{e.message.lines.first.to_s.strip}")
    end

    def judge(cdp, surface)
      cdp.navigate(surface.url, settle: SETTLE_S)
      vitals = JSON.parse(cdp.evaluate(COLLECT, await_promise: true).to_s)
      @result.checked!(2)
      judge_lcp(surface, vitals["lcp"])
      judge_cls(surface, vitals["cls"])
    end

    # A missing metric is not a passing one. LCP is absent on a page that painted
    # nothing large enough to qualify, and reporting that as within budget is the
    # measured-nothing failure this suite already refuses elsewhere.
    def judge_lcp(surface, value)
      return @result.inconclusive!("web_vitals_budget: #{surface.label} reported no LCP entry") if value.nil?
      return if value <= LCP_BUDGET_MS

      @result.fail("web_vitals_budget: #{surface.label} LCP #{value.round}ms over #{LCP_BUDGET_MS}ms")
    end

    def judge_cls(surface, value)
      return @result.inconclusive!("web_vitals_budget: #{surface.label} reported no CLS entry") if value.nil?
      return if value <= CLS_BUDGET

      @result.fail("web_vitals_budget: #{surface.label} CLS #{value.round(3)} over #{CLS_BUDGET}")
    end

    def rel(path) = path.sub("#{ROOT}/", "")

    # Observers registered, then the page's own buffered entries replayed, so
    # this reads a load that has already happened rather than waiting for a
    # second one. `buffered: true` is what makes that work.
    COLLECT = <<~JS
      new Promise((resolve) => {
        let lcp = null
        let cls = 0
        let sawShift = false
        try {
          new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) lcp = entry.startTime
          }).observe({ type: "largest-contentful-paint", buffered: true })
          new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) {
              sawShift = true
              if (!entry.hadRecentInput) cls += entry.value
            }
          }).observe({ type: "layout-shift", buffered: true })
        } catch (e) {
          resolve(JSON.stringify({ lcp: null, cls: null }))
          return
        }
        setTimeout(() => resolve(JSON.stringify({ lcp, cls: sawShift ? cls : 0 })), 400)
      })
    JS
  end
end
