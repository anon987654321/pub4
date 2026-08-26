# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../tools/crawl_support"
require_relative "../../support/exemplar_structure"
require_relative "../../support/visual_quality"

module Deploy
  # P3: exemplar structure distance + visual quality (not pixel baseline).
  # Fixtures always run; live HTML when ports open; optional PNG ink ratio.
  class VisualQualityGate
    ROOT = File.expand_path("../../../..", __dir__)
    FIXTURES = File.join(File.expand_path("../..", __dir__), "fixtures", "exemplars")
    VISUAL_DIR = File.join(ROOT, "RAILS", "visual_contract")

    # exemplar_id => path under fixtures or live probe
    FIXTURE_MAP = {
      "marketplace_tile" => "good_marketplace_tile.html",
      "dating_card" => "good_dating_card.html",
      "live_card" => "good_live_card.html",
      "marketplace_first_screen" => "good_marketplace_first_screen.html",
    }.freeze

    BAD_FIXTURE_MAP = {
      "marketplace_tile" => "bad_marketplace_tile.html",
      "dating_card" => "bad_dating_card.html",
      "live_card" => "bad_live_card.html",
    }.freeze

    LIVE_PROBES = [
      {
        exemplar: "marketplace_first_screen",
        quality_surface: :marketplace,
        app: "brgen",
        path: "/",
        host: "markedsplass.brgen.no",
      },
      {
        exemplar: nil,
        quality_surface: :live,
        app: "brgen",
        path: "/live",
        host: "brgen.no",
      },
      {
        exemplar: nil,
        quality_surface: :dating,
        app: "brgen",
        path: "/",
        host: "dating.brgen.no",
      },
    ].freeze

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      @exemplars = ExemplarStructure.new
      @quality = VisualQuality.new
      run_good_fixtures
      run_bad_fixtures
      run_live
      optional_png_ink
      @result
    end

    private

    def run_good_fixtures
      FIXTURE_MAP.each do |id, file|
        path = File.join(FIXTURES, file)
        unless File.file?(path)
          @result.fail("visual_quality: missing good fixture #{file}")
          next
        end
        html = File.read(path)
        r = @exemplars.score(html, id)
        apply_exemplar_result!(r, context: "fixture good/#{id}")

        # Page-level quality rubric only on full documents (not card partials).
        next unless html.match?(/<main\b|<html\b/i)

        surface = dialect_surface(id)
        q = @quality.score(html, surface: surface)
        apply_quality_result!(q, context: "fixture good/#{id}")
      end
    end

    def run_bad_fixtures
      BAD_FIXTURE_MAP.each do |id, file|
        path = File.join(FIXTURES, file)
        unless File.file?(path)
          @result.warn("visual_quality: missing bad fixture #{file}")
          next
        end
        r = @exemplars.score(File.read(path), id)
        if r.pass?
          @result.fail("visual_quality: bad fixture #{id} unexpectedly passed (score #{r.score}/#{r.max}) — gate blind")
        else
          @result.warn("visual_quality: bad/#{id} correctly scored #{r.score}/#{r.max} (target #{r.target})")
        end
      end
    end

    def run_live
      inventory = Inventory.new(root: ROOT).apps.to_h { |a| [a.name, a] }
      LIVE_PROBES.each do |probe|
        app = inventory[probe[:app]]
        unless app
          @result.fail("visual_quality: unknown app #{probe[:app]}")
          next
        end
        unless CrawlSupport.port_open?("127.0.0.1", app.port)
          @result.skipped_live("visual_quality: live #{probe[:quality_surface]} skipped (port closed)")
          next
        end
        html = fetch("http://127.0.0.1:#{app.port}#{probe[:path]}", host: probe[:host])
        if html.nil?
          @result.fail("visual_quality: live fetch failed #{probe[:host]}#{probe[:path]}", severity: :soft)
          next
        end

        if probe[:exemplar]
          r = @exemplars.score(html, probe[:exemplar])
          apply_exemplar_result!(r, context: "live #{probe[:exemplar]}")
        end
        q = @quality.score(html, surface: probe[:quality_surface])
        apply_quality_result!(q, context: "live #{probe[:quality_surface]}")
      end
    end

    def optional_png_ink
      samples = %w[
        brgen-public-desktop.png
        brgen-marketplace-desktop.png
        brgen-public-mobile.png
      ]
      ratios = []
      samples.each do |name|
        path = File.join(VISUAL_DIR, name)
        next unless File.file?(path)

        ratio = @quality.png_ink_ratio(path)
        next unless ratio

        ratios << [name, ratio]
        # Washed/empty or crushed canvases have almost no midtone signal.
        if ratio < 0.02
          @result.fail("visual_quality png: #{name} content_ratio #{ratio} looks empty (principle=signal_noise)", severity: :soft)
        elsif ratio > 0.98
          @result.fail("visual_quality png: #{name} content_ratio #{ratio} looks noisy/crushed (principle=signal_noise)", severity: :soft)
        end
      end
      @result.warn("visual_quality png: content sampled #{ratios.map { |n, r| "#{n}=#{r}" }.join(', ')}") if ratios.any?
    end

    def apply_exemplar_result!(r, context:)
      if r.missing_required.any?
        return @result.fail(
          "#{context}: exemplar #{r.id} missing required #{r.missing_required.join(', ')} (#{r.score}/#{r.max})",
          severity: :hard
        )
      end

      unless r.pass?
        return @result.fail(
          "#{context}: exemplar #{r.id} score #{r.score}/#{r.max} < target #{r.target} notes=#{r.notes.join(',')}",
          severity: :soft
        )
      end

      @result.warn("#{context}: exemplar #{r.id} #{r.score}/#{r.max} (#{(r.ratio * 100).round}%)")
    end

    def apply_quality_result!(q, context:)
      return @result.warn("#{context}: quality #{q.score}/#{q.max}") if q.pass?

      @result.fail(
        "#{context}: quality #{q.score}/#{q.max} < target #{q.target} notes=#{q.notes.join(',')} principle=venustas",
        severity: :soft
      )
    end

    def dialect_surface(exemplar_id)
      case exemplar_id.to_s
      when /marketplace/ then :marketplace
      when /dating/ then :dating
      when /live/ then :live
      else :generic
      end
    end

    def fetch(url, host: nil)
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 15) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Host"] = host if host
        http.request(req)
      end
      return nil unless res.code.to_i.between?(200, 399)

      res.body.to_s
    rescue StandardError # scan: intentional — nil is the measured-nothing signal, reported downstream as the gate's warning
      nil
    end
  end
end
