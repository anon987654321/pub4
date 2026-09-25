# frozen_string_literal: true

require "zlib"

class WardrobeAi
  # The no-model answers. See wardrobe_ai/offline.rb — most machines and vm23
  # by default have no OPENROUTER_API_KEY, so that path is the common one.
  include Offline

  MODEL = Shared::Llm::DEFAULT_MODEL

  def self.configured?
    Shared::Llm.configured?
  end

  def self.master_photograph_available?
    return false if ENV["CI"] == "1" || Rails.env.test?
    return false unless ENV["AMBER_ENABLE_MASTER_PHOTO"].to_s == "1"

    Operator::DeployPaths.master_root.present?
  end

  # Pass client: nil to force offline heuristics (explicit); omit for auto OpenRouter.
  def initialize(user, client: :auto)
    @user = user
    @client = client == :auto ? build_client : client
  end

  def available? = @client.present?

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
      r["source"]     ||= @client ? "openrouter" : "heuristic"
    end
  end

  def suggest_outfits(occasion: nil, season: nil)
    items = @user.items.joy.active_wardrobe.limit(20).to_a
    items = @user.items.active_wardrobe.limit(20).to_a if items.empty?
    return rule_based_outfits(items, occasion:, season:) if items.empty? || !@client

    items_summary = items.map { |i| "#{i.title} (#{i.category}, #{i.color})" }.join(", ")
    prompt = <<~PROMPT
      You are a fashion stylist with vision. Suggest 3 outfit combinations (3 items each) from the wardrobe.
      Use both the text metadata and the attached photos to judge fit, colour harmony, style, and occasion.
      #{occasion ? "Occasion: #{occasion}" : ""}
      #{season ? "Season: #{season}" : ""}
      Items: #{items_summary}
      Reply ONLY with JSON: {"outfits": [{"name": "outfit name", "items": ["item title 1", "item title 2", "item title 3"], "description": "why it works"}]}
    PROMPT
    vision_items = items.select { |i| i.photos.attached? }.first(5)
    attachments = vision_items.filter_map { |item| item.photos.first if item.photos.attached? }
    outfits = chat(prompt, with: attachments.presence)["outfits"] || []
    outfits = rule_based_outfits(items, occasion:, season:) if outfits.blank?
    Array(outfits).each { |o| o["source"] ||= @client ? "openrouter" : "rule" if o.is_a?(Hash) }
    outfits
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
      return result.merge("source" => "openrouter") if result["palette"].present?
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
    if @client
      prompt = <<~PROMPT
        Suggest 5-8 outfits from the user's wardrobe for a #{duration}-day trip in #{climate} climate.
        Return JSON: {"outfits": [{"name": "outfit name", "items": ["item title 1", "item title 2"]}, ...], "tips": "brief packing tip"}
        User wardrobe: #{@user.items.limit(10).map { |i| "#{i.title} (#{i.category}, #{i.color}, #{i.season})" }.join("; ")}
      PROMPT
      result = chat(prompt)
      return result if result["outfits"].present?
    end

    items = @user.items.active_wardrobe.limit(8)
    {
      "outfits" => items.each_slice(3).with_index.map { |slice, i|
        { "name" => "Day #{i + 1}", "items" => slice.map(&:title) }
      },
      "tips" => "Rule-based pack from active wardrobe (#{duration} days, #{climate}).",
      "source" => "heuristic"
    }
  end

  private

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
