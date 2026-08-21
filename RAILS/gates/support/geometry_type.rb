# frozen_string_literal: true

require "yaml"

module Deploy
  # Worn-type contracts. rules.yml design_rules.worn_type is the law; this module
  # is the reader. A profile that exists only in YAML is inert — MASTER
  # test_design_rules_worn_type.rb fails if a profile name is missing here.
  module GeometryType
    RULES = File.join(File.expand_path("../../..", __dir__), "MASTER", "data", "rules.yml")

    LABEL_PROFILES = {
      "marketplace" => "catalog", "marketplace_cart" => "catalog",
      "marketplace_deals" => "catalog", "marketplace_sell" => "catalog",
      "marketplace_shops" => "catalog",
      "takeaway" => "catalog", "takeaway_orders" => "catalog", "takeaway_drivers" => "catalog",
      "wardrobe" => "catalog", "demo" => "catalog", "outfits" => "catalog", "upload" => "catalog",
      "ports_index" => "catalog", "search_results" => "catalog", "empty_results" => "catalog",
      "dating" => "immersive", "dating_profile_new" => "catalog", "dating_matches" => "catalog",
      "playlist" => "immersive", "playlist_sets" => "immersive", "playlist_hosted" => "immersive",
      "tv" => "immersive", "tv_channels" => "immersive", "tv_live_streams" => "immersive",
      "maps" => "map", "maps_places" => "map",
      "messenger" => "chat", "conversations" => "chat",
      "session_new" => "auth", "sign_in" => "auth",
      "privacy" => "legal", "terms" => "legal", "cookies" => "legal",
    }.freeze

    WALK = File.read(File.join(__dir__, "geometry_type_walk.js"))

    module_function

    def probe(cdp)
      cdp.evaluate(WALK)
    rescue StandardError => e
      warn "geometry_type: DOM walk failed (#{e.class}) — surface measured as empty"
      {}
    end

    def rules
      @rules ||= ((YAML.safe_load_file(RULES, aliases: true) if File.file?(RULES)) || {})["design_rules"] || {}
    end

    def worn
      rules["worn_type"] || {}
    end

    def profile_for(label)
      LABEL_PROFILES[label.to_s] ||
        (label.to_s.start_with?("marketplace", "takeaway") ? "catalog" : "feed")
    end

    def profile(label)
      name = profile_for(label)
      defaults = worn.dig("profiles", "feed") || {}
      spec = worn.dig("profiles", name) || {}
      defaults.merge(spec).merge("name" => name)
    end

    def check(result, surface, data)
      spec = profile(surface.label)
      check_measure(result, surface, data, spec)
      check_type_scale(result, surface, data, spec)
      check_baseline(result, surface, data, spec)
      check_tabular(result, surface, data, spec)
      check_accents(result, surface, data, spec)
      check_empty(result, surface, data, spec)
      check_split(result, surface, data, spec)
      check_hanging(result, surface, data, spec)
      spec
    end

    def check_measure(result, surface, data, spec)
      min = spec["measure_min_ch"].to_f
      max = spec["measure_max_ch"].to_f
      return if min <= 0 && max <= 0

      rows = Array(data["prose"])
      return if rows.empty?

      mobile = surface.width.to_i <= 480
      min = spec["mobile_min_ch"].to_f if mobile && spec["mobile_min_ch"]
      max = spec["mobile_max_ch"].to_f if mobile && spec["mobile_max_ch"]
      return if max <= 0

      bad = rows.select { |r| ch = r["ch"].to_i; ch.positive? && (ch < min || ch > max) }
      return if bad.empty? || bad.size < 2

      sample = bad.first(3).map { |r| "#{r["sel"]} #{r["ch"]}ch" }.join("; ")
      result.fail(
        "geometry measure: #{surface.id} #{bad.size} prose run(s) outside #{min.to_i}–#{max.to_i}ch " \
        "(profile=#{spec["name"]}) — #{sample} (principle=bringhurst)",
        severity: :soft
      )
    end

    def check_type_scale(result, surface, data, spec)
      sizes = data["type_sizes"]
      return unless sizes.is_a?(Hash) && sizes.size > 1

      ratio = (worn["type_scale_ratio"] || 1.25).to_f
      tol = (worn["type_scale_tolerance_px"] || 1.5).to_f
      body = sizes.max_by { |_px, n| n }&.first.to_f
      return if body <= 0

      steps = (0..8).map { |i| (body * (ratio**i)).round(1) }
      steps.concat((1..4).map { |i| (body / (ratio**i)).round(1) })
      stray = sizes.keys.map(&:to_f).reject { |px| steps.any? { |s| (px - s).abs <= tol } }
      return if stray.empty?

      result.fail(
        "geometry type_scale: #{surface.id} computed sizes #{stray.sort.map { |s| "#{s}px" }.join(", ")} " \
        "sit off the #{ratio} scale from body #{body}px (principle=ruder)",
        severity: :soft
      )
    end

    def check_baseline(result, surface, data, spec)
      mod = (worn["baseline_module_px"] || 4).to_f
      rows = Array(data["baselines"])
      return if rows.size < 3

      off = rows.reject { |r| ((r["y"].to_f / mod) - (r["y"].to_f / mod).round).abs < 0.2 }
      ratio = off.size.to_f / rows.size
      return if ratio < 0.4

      result.fail(
        "geometry baseline: #{surface.id} #{off.size}/#{rows.size} first-line baselines off the " \
        "#{mod.to_i}px module (principle=hochuli)",
        severity: :soft
      )
    end

    def check_tabular(result, surface, data, spec)
      return unless spec["require_tabular_nums"]

      rows = Array(data["tabular"])
      return if rows.empty?

      missing = rows.reject { |r| r["numeric"].to_s.include?("tabular-nums") }
      return if missing.empty?

      sample = missing.first(3).map { |r| r["sel"] }.join("; ")
      result.fail(
        "geometry tabular: #{surface.id} #{missing.size} quantity run(s) without tabular-nums — " \
        "#{sample} (principle=catalog_figures)",
        severity: :soft
      )
    end

    def check_accents(result, surface, data, spec)
      max = spec["accents_max"].to_i
      return if max <= 0

      hues = data["accent_hues"]
      return unless hues.is_a?(Hash)

      live = hues.select { |_h, n| n.to_i >= 8 }.keys
      return if live.size <= max

      result.fail(
        "geometry accents: #{surface.id} wears #{live.size} accent hues #{live.sort.join(", ")} " \
        "(max #{max} for profile=#{spec["name"]}) (principle=vignelli)",
        severity: :soft
      )
    end

    def check_empty(result, surface, data, spec)
      ratio = data["empty_ratio"]
      return unless ratio

      min = spec["empty_min_pct"].to_f / 100.0
      max = spec["empty_max_pct"].to_f / 100.0
      return if max <= 0

      if ratio < min || ratio > max
        result.fail(
          "geometry empty_ratio: #{surface.id} #{(ratio * 100).round}% empty " \
          "(profile=#{spec["name"]} wants #{spec["empty_min_pct"]}-#{spec["empty_max_pct"]}%) " \
          "(principle=ma)",
          severity: :soft
        )
      end
    end

    def check_split(result, surface, data, spec)
      split = data["split"]
      return unless split.is_a?(Hash)

      golden = rules.dig("layout_rules", "proportion") || {}
      target = (golden["split_main_ratio"] || worn.dig("golden_split", "min") || 0.618).to_f
      band = worn["golden_split"] || {}
      min = (band["min"] || target - 0.07).to_f
      max = (band["max"] || target + 0.07).to_f
      ratio = split["ratio"].to_f
      return if ratio.between?(min, max)

      result.fail(
        "geometry split: #{surface.id} main/aside #{split["main"]}px/#{split["aside"]}px " \
        "(#{ratio}) outside #{min}-#{max} (principle=modulor)",
        severity: :soft
      )
    end

    def check_hanging(result, surface, data, spec)
      rows = Array(data["hanging"])
      return if rows.empty?

      inset = (worn["hanging_marker_max_inset_px"] || 0).to_f
      bad = rows.select { |r| r["marker_x"].to_f > r["text_x"].to_f + inset + 0.5 }
      return if bad.empty?

      sample = bad.first(3).map { |r| "#{r["sel"]} marker #{r["marker_x"]} > text #{r["text_x"]}" }.join("; ")
      result.fail(
        "geometry hanging: #{surface.id} #{bad.size} list marker(s) sit inside the measure — " \
        "#{sample} (principle=tschichold)",
        severity: :soft
      )
    end
  end
end
