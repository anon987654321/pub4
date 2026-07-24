# frozen_string_literal: true

require "yaml"

module Deploy
  # Multi-axis marketplace layout search (P4).
  # Enumerates the finite candidate space, applies hard floors, scores with
  # Fitts/Hick/resistance/catalog objectives, reports winner ranking.
  class LayoutSearch
    DATA = File.join(File.expand_path("..", __dir__), "data", "layout_search.yml")

    Candidate = Struct.new(
      :id, :axes, :score, :breakdown, :hard_ok, :illegal, keyword_init: true
    ) do
      def legal?
        !illegal && hard_ok
      end
    end

    Observation = Struct.new(:axes, :id, keyword_init: true)

    def self.load(path = DATA)
      YAML.safe_load_file(path)
    end

    def initialize(config: nil)
      @config = config || self.class.load
      @axes = @config.fetch("axes")
      @combos = Array(@config["combo_bonuses"])
      @target = @config["target_score"].to_i
      @max_rank = [@config["max_winner_rank"].to_i, 1].max
      @hard_required = @config["hard_required"] || {}
    end

    attr_reader :target, :max_rank, :hard_required

    # ctx: { card:, nav:, search:, cards_css: optional }
    def observe(ctx)
      axes = {}
      @axes.each_key do |axis|
        axes[axis.to_s] = detect_variant(axis.to_s, ctx).to_s
      end
      Observation.new(axes: axes, id: candidate_id(axes))
    end

    def enumerate(ctx = nil)
      keys = @axes.keys.map(&:to_s)
      variant_lists = keys.map { |k| @axes[k]["variants"].keys.map(&:to_s) }
      product(variant_lists).map do |combo|
        axes = keys.zip(combo).to_h
        build_candidate(axes, ctx)
      end
    end

    def rank(ctx)
      enumerate(ctx).select(&:legal?).sort_by { |c| [-c.score, c.id] }
    end

    def winner(ctx)
      rank(ctx).first
    end

    def report(ctx)
      observed = observe(ctx)
      ranking = rank(ctx)
      win = ranking.first
      obs_candidate = ranking.find { |c| c.id == observed.id } || build_candidate(observed.axes, ctx)
      obs_rank = ranking.index { |c| c.id == observed.id }
      obs_rank = obs_rank ? obs_rank + 1 : nil

      {
        observed: observed,
        observed_candidate: obs_candidate,
        observed_rank: obs_rank,
        winner: win,
        ranking: ranking,
        target: @target,
        max_rank: @max_rank,
        hard_required_ok: hard_required_ok?(observed.axes),
        space_size: enumerate.size,
        legal_size: ranking.size,
      }
    end

    private

    def build_candidate(axes, ctx)
      breakdown = { catalog: 0, fitts: 0, hick: 0, resistance: 0, combo: 0 }
      hard_ok = true
      illegal = false

      axes.each do |axis, variant|
        spec = @axes.dig(axis, "variants", variant)
        unless spec
          illegal = true
          next
        end
        scores = spec["scores"] || {}
        scores.each { |k, v| breakdown[k.to_sym] = breakdown[k.to_sym].to_i + v.to_i }
        # hard: variant marked hard:false is still legal; hard_required checked separately
      end

      @combos.each do |combo|
        when_h = combo["when"] || {}
        next unless when_h.all? { |a, v| axes[a.to_s] == v.to_s }

        bonus = combo["bonus"].to_i
        breakdown[:combo] += bonus
      end

      # Soft total: higher better. resistance is stored as "cost" deltas (positive = worse),
      # so invert resistance contribution for total desirability.
      total =
        breakdown[:catalog].to_i +
        breakdown[:fitts].to_i +
        breakdown[:hick].to_i +
        breakdown[:combo].to_i -
        breakdown[:resistance].to_i

      # Optional: if ctx given, tiny boost when detect matches (already encoded in axes)
      _ = ctx

      hard_ok = hard_required_ok?(axes)

      Candidate.new(
        id: candidate_id(axes),
        axes: axes,
        score: total,
        breakdown: breakdown,
        hard_ok: hard_ok,
        illegal: illegal
      )
    end

    def hard_required_ok?(axes)
      @hard_required.all? { |axis, variant| axes[axis.to_s] == variant.to_s }
    end

    def candidate_id(axes)
      @axes.keys.map(&:to_s).map { |k| "#{k}=#{axes[k]}" }.join("|")
    end

    def detect_variant(axis, ctx)
      card = ctx[:card].to_s
      nav = ctx[:nav].to_s
      search = ctx[:search].to_s

      case axis
      when "price_placement"
        price_i = card.index("deal-price")
        title_i = card.index("deal-card-title")
        return "price_first" if price_i && title_i && price_i < title_i
        return "title_first" if price_i && title_i
        "title_first"
      when "media_placement"
        img = card.index("deal-card-img") || card.index("deal-card-media")
        body = card.index("deal-card-body")
        return "photo_first" if img && body && img < body
        return "body_first" if img && body
        "body_first"
      when "hit_model"
        if card.include?("deal-card-hit") || card.match?(/link_to.*deal-card/)
          "whole_card"
        elsif card.scan(/button_to|deal-cta/).size > 2
          "multi_cta"
        else
          "multi_cta"
        end
      when "nav_model"
        nav.include?("navBar") || nav.include?('id="navBar"') ? "amazon_nav" : "plain_nav"
      when "search_model"
        if search.include?(".search") && search.include?("border-radius: 30px")
          "yep_search"
        else
          "plain_search"
        end
      else
        @axes.dig(axis, "variants")&.keys&.first.to_s
      end
    end

    def product(lists)
      return [[]] if lists.empty?

      lists[0].product(*lists[1..])
    end
  end
end
