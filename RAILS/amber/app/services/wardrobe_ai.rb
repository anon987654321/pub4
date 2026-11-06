# frozen_string_literal: true

require "zlib"
require "shared/contracts"
Shared::Contracts.require_contract("studio")

class WardrobeAi
  # The no-model answers. See wardrobe_ai/offline.rb — most machines and vm23
  # by default have no OPENROUTER_API_KEY, so that path is the common one.
  include Offline

  MODEL = Shared::Llm::DEFAULT_MODEL
  PROVIDER_SOURCE = Shared::Llm::PROVIDER.to_s

  def self.configured?
    Shared::Llm.configured?
  end

  def self.studio_photograph_available?
    return false if ENV["CI"] == "1" || Rails.env.test?
    return false unless ENV["AMBER_ENABLE_STUDIO_PHOTO"].to_s == "1"

    Contracts::Studio.photograph_script.present?
  end

  # Pass client: nil to force offline heuristics (explicit); omit for auto OpenRouter.
  def initialize(user, client: :auto)
    @user = user
    # Consent is checked even for an injected client. Missing settings and
    # failed lookups fail closed; local rules remain available.
    @client = if remote_ai_allowed?
      client == :auto ? build_client : client
    end
  end

  def available? = @client.present?

  # Whether consent allows an external processing path, independent of whether
  # a particular provider is configured or reachable.
  def external_processing_allowed? = remote_ai_allowed?

  def analyze_joy(item)
    prompt = <<~PROMPT
      Analyze this clothing item from a Marie Kondo perspective.
      Reply with JSON: {"sparks_joy": true/false, "reason": "brief explanation", "suggestion": "action to take"}

      Item: #{item.title}
      Category: #{item.category}
      Color: #{item.color}
      Times worn: #{item.times_worn || 0}
      Age: #{item.purchase_date ? "#{((Date.current - item.purchase_date) / 365).to_i} years" : "unknown"}
    PROMPT

    result = if @client
      chat(prompt)
    else
      heuristic_joy(item)
    end

    result.tap do |r|
      r["sparks_joy"] = nil unless r.key?("sparks_joy")
      r["reason"]     ||= "Analysis unavailable"
      r["suggestion"] ||= "Trust your instincts"
      r["source"]     ||= @client ? PROVIDER_SOURCE : "heuristic"
    end
  end

  def suggest_outfits(occasion: nil, season: nil)
    items = @user.items.joy.in_rotation.limit(20).to_a
    items = @user.items.in_rotation.limit(20).to_a if items.empty?
    return [] if items.empty?

    unless @client
      return normalize_outfits(rule_based_outfits(items, occasion:, season:), items)
    end

    items_summary = items.map { |item| "#{item.id}: #{item.title} (#{item.category}, #{item.color})" }.join(", ")
    prompt = <<~PROMPT
      Suggest up to 3 outfit combinations from the listed garments.
      Every garment starts with its unique numeric ID. Return JSON only:
      {"outfits":[{"name":"outfit name","item_ids":[123,456,789],"description":"why it works"}]}
      Use only IDs from the supplied catalogue. Never invent IDs or substitute garments.
      #{occasion ? "Occasion: #{occasion}" : ""}
      #{season ? "Season: #{season}" : ""}
      Garments: #{items_summary}
    PROMPT
    attachments = items.select { |item| item.photos.attached? }.first(5).filter_map do |item|
      item.photos.first if item.photos.attached?
    end
    outfits = chat(prompt, with: attachments.presence)["outfits"] || []
    outfits = rule_based_outfits(items, occasion:, season:) if outfits.blank?
    normalize_outfits(outfits, items)
  end

  def declutter_candidates
    @user.items.aging_unworn.order(price_cents: :desc)
  end

  def capsule_optimizer
    if @client
      catalog = @user.items.map { |i| "#{i.id}:#{i.title}(#{i.category},#{i.color})" }.join("; ")
      prompt = <<~P
        You are a capsule wardrobe expert. Given this wardrobe catalog, select a minimum keep-set
        that maximises outfit combinations. For each item return: keep/consider/release and reason.
        Respond with JSON: {"items":[{"id":N,"title":"...","decision":"keep|consider|release","reason":"..."}],"gap_items":["description of missing pieces"]}
        Catalog: #{catalog}
      P
      result = chat(prompt)
      return result if result["items"].present?
    end

    offline_capsule
  end

  def color_palette_analysis
    if @client
      items_desc = @user.items.map { |i| "#{i.title}: #{i.color}" }.join(", ")
      prompt = <<~P
        Analyse this wardrobe color list and identify the dominant palette, harmony gaps,
        and any clashing items. Map to a seasonal color system where possible.
        Respond with JSON: {"palette":"...","season_type":"...","harmonious":["item desc"],"clashing":["item desc"],"suggestions":["..."]}
        Items: #{items_desc}
      P
      result = chat(prompt)
      return result.merge("source" => PROVIDER_SOURCE) if result["palette"].present?
    end

    offline_palette
  end

  def natural_language_search(query)
    catalog = @user.items.map { |i| "id=#{i.id} #{i.title} #{i.category} #{i.color} #{i.material} #{i.occasion_tags} #{i.season}" }.join("\n")
    if @client
      prompt = <<~P
        From this wardrobe, find items matching: "#{query}"
        Return JSON: {"item_ids":[array of matching ids],"explanation":"..."}
        Wardrobe:
        #{catalog}
      P
      result = chat(prompt)
      return result if Array(result["item_ids"]).any?
    end

    offline_search(query)
  end

  def mood_board_match(description)
    catalog = @user.items.map { |i| "id=#{i.id} #{i.title} #{i.category} #{i.color} #{i.material}" }.join("\n")
    if @client
      prompt = <<~P
        Style reference: "#{description}"
        From this wardrobe, suggest the best outfit matching that aesthetic.
        Return JSON: {"item_ids":[array of ids],"outfit_name":"...","description":"why this matches"}
        Wardrobe:
        #{catalog}
      P
      result = chat(prompt)
      return result if Array(result["item_ids"]).any?
    end

    offline_search(description).merge(
      "outfit_name" => "Closet match",
      "description" => "Keyword match from your wardrobe (rule-based; enable OpenRouter for styled matching)."
    )
  end

  def enclothed_cognition_tag(item)
    if @client
      prompt = <<~P
        For this clothing item, suggest the most likely psychological/mood effect when worn.
        Choose one: energising, calming, confident, playful, neutral.
        Also suggest life_phase: current, past-self, or aspirational.
        Reply JSON: {"mood_effect":"...","life_phase":"...","reason":"..."}
        Item: #{item.title}, category: #{item.category}, color: #{item.color}, brand: #{item.brand}
      P
      result = chat(prompt)
      return result if result["mood_effect"].present?
    end

    {
      "mood_effect" => item.mood_effect.presence || "neutral",
      "life_phase" => item.life_phase.presence || "current",
      "reason" => "Heuristic default (OpenRouter not configured).",
      "source" => "heuristic"
    }
  end

  # Local deterministic fingerprint — NOT a semantic embedding. Real pgvector embeddings are planned.
  def fingerprint_for(item)
    text = item.embedding_text.to_s
    seed = Zlib.crc32(text)
    Array.new(64) do |index|
      (((seed + index * 1_103_515_245) % 10_000) / 10_000.0).round(6)
    end
  end
  alias embedding_for fingerprint_for

  def infer_style_profile(answers)
    prompt = <<~PROMPT
      User answered these 5 style profile questions. Infer primary aesthetic as one of: minimal, bold, classic.
      Return JSON only: {"aesthetic": "minimal|bold|classic", "reason": "short", "suggestions": ["item type 1", "item type 2"]}
      Answers: #{answers.inspect}
      Current wardrobe sample: #{@user.items.limit(3).map { |i| "#{i.title} (#{i.category}, #{i.color})" }.join("; ")}
    PROMPT
    result = @client ? chat(prompt) : {}
    return result if result["aesthetic"].present?

    { "aesthetic" => "minimal", "reason" => "Default without AI key", "suggestions" => %w[tops bottoms shoes], "source" => "heuristic" }
  end

  def suggest_packing_list(duration, climate)
    items = @user.items.in_rotation.limit(10).to_a
    if @client && items.any?
      catalog = items.map { |item| "#{item.id}: #{item.title} (#{item.category}, #{item.color}, #{item.season})" }.join("; ")
      prompt = <<~PROMPT
        Suggest 5-8 day-by-day outfit groups for a #{duration}-day trip in #{climate} climate.
        Only use these wardrobe garments, each identified by its numeric ID.
        Return JSON: {"outfits":[{"name":"Day 1","item_ids":[12,34]}],"tips":"brief packing tip"}.
        Do not invent or replace IDs. Wardrobe: #{catalog}
      PROMPT
      result = chat(prompt)
      outfits = normalize_outfits(result["outfits"], items)
      return result.merge("outfits" => outfits) if outfits.present?
    end

    items = @user.items.in_rotation.limit(8).to_a if items.empty?
    {
      "outfits" => items.each_slice(3).with_index.map do |slice, index|
        { "name" => "Day #{index + 1}", "items" => slice.map(&:title), "item_ids" => slice.map(&:id) }
      end,
      "tips" => "Rule-based pack from active wardrobe (#{duration} days, #{climate}).",
      "source" => "heuristic"
    }
  end

  private

  def remote_ai_allowed?
    @user.present? &&
      PrivacySetting.where(user_id: @user.id, allow_ai_analysis: true).exists?
  rescue StandardError => e
    Rails.logger.warn("WardrobeAi consent check failed; using local rules: #{e.class}")
    false
  end

  def normalize_outfits(outfits, candidates)
    by_id = candidates.index_by(&:id)
    by_title = candidates.group_by { |item| item.title.to_s.strip.downcase }

    Array(outfits).filter_map do |outfit|
      next unless outfit.is_a?(Hash)

      ids = Array(outfit["item_ids"]).filter_map do |value|
        value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
      end.select { |id| by_id.key?(id) }.uniq
      if ids.empty?
        ids = Array(outfit["items"]).filter_map do |label|
          title = label.to_s.split("(").first.strip.downcase
          matches = by_title.fetch(title, [])
          matches.one? ? matches.first.id : nil
        end.uniq
      end
      next if ids.empty?

      outfit.merge(
        "item_ids" => ids,
        "items" => ids.map { |id| by_id.fetch(id).title },
        "source" => outfit["source"].presence || (@client ? PROVIDER_SOURCE : "rule")
      )
    end
  end

  def build_client
    return nil unless Shared::Llm.configured?

    Shared::Llm.new(model: MODEL)
  end

  def chat(prompt, with: nil)
    return fallback_response(prompt) unless @client

    content = @client.ask(prompt, with:)
    return fallback_response(prompt) if content.blank?

    JSON.parse(content)
  rescue JSON::ParserError => e
    Rails.logger.warn("WardrobeAI invalid JSON: #{e.message}")
    fallback_response(prompt)
  rescue StandardError => e
    Rails.logger.error("WardrobeAI error: #{e.class}: #{e.message}")
    fallback_response(prompt)
  end
end
