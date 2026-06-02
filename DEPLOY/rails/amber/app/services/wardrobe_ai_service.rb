# frozen_string_literal: true

require "zlib"

class WardrobeAiService
  OPENROUTER_BASE = "https://openrouter.ai/api/v1"
  MODEL = "google/gemini-2.0-flash-001"

  def initialize(user, client: nil)
    @user = user
    @client = client || build_client
  end

  def analyze_joy(item)
    prompt = <<~PROMPT
      Analyze this clothing item from a Marie Kondo perspective.
      Reply with JSON: {"sparks_joy": true/false, "reason": "brief explanation", "suggestion": "action to take"}

      Item: #{item.title}
      Category: #{item.category}
      Color: #{item.color}
      Times worn: #{item.times_worn || 0}
      Age: #{item.purchase_date ? "#{((Date.today - item.purchase_date) / 365).to_i} years" : "unknown"}
    PROMPT

    chat(prompt).tap do |r|
      r["sparks_joy"] = nil unless r.key?("sparks_joy")
      r["reason"]     ||= "Analysis unavailable"
      r["suggestion"] ||= "Trust your instincts"
    end
  end

  def suggest_outfits(occasion: nil, season: nil)
    items_summary = @user.items.joy.limit(20).map { |i| "#{i.title} (#{i.category}, #{i.color})" }.join(", ")
    prompt = <<~PROMPT
      Suggest 3 outfit combinations from these wardrobe items.
      #{occasion ? "Occasion: #{occasion}" : ""}
      #{season ? "Season: #{season}" : ""}
      Items: #{items_summary}
      Reply with JSON: {"outfits": [{"name": "outfit name", "items": ["item1", ...], "description": "why it works"}]}
    PROMPT
    chat(prompt)["outfits"] || []
  end

  def declutter_candidates
    @user.items.aging_unworn.order(price: :desc)
  end

  def capsule_optimizer
    catalog = @user.items.map { |i| "#{i.id}:#{i.title}(#{i.category},#{i.color})" }.join("; ")
    prompt = <<~P
      You are a capsule wardrobe expert. Given this wardrobe catalog, select a minimum keep-set
      that maximises outfit combinations. For each item return: keep/consider/release and reason.
      Respond with JSON: {"items":[{"id":N,"title":"...","decision":"keep|consider|release","reason":"..."}],"gap_items":["description of missing pieces"]}
      Catalog: #{catalog}
    P
    chat(prompt)
  end

  def color_palette_analysis
    items_desc = @user.items.map { |i| "#{i.title}: #{i.color}" }.join(", ")
    prompt = <<~P
      Analyse this wardrobe color list and identify the dominant palette, harmony gaps,
      and any clashing items. Map to a seasonal color system where possible.
      Respond with JSON: {"palette":"...","season_type":"...","harmonious":["item desc"],"clashing":["item desc"],"suggestions":["..."]}
      Items: #{items_desc}
    P
    chat(prompt)
  end

  def natural_language_search(query)
    catalog = @user.items.map { |i| "id=#{i.id} #{i.title} #{i.category} #{i.color} #{i.material} #{i.occasion_tags} #{i.season}" }.join("\n")
    prompt = <<~P
      From this wardrobe, find items matching: "#{query}"
      Return JSON: {"item_ids":[array of matching ids],"explanation":"..."}
      Wardrobe:
      #{catalog}
    P
    chat(prompt)
  end

  def mood_board_match(description)
    catalog = @user.items.map { |i| "id=#{i.id} #{i.title} #{i.category} #{i.color} #{i.material}" }.join("\n")
    prompt = <<~P
      Style reference: "#{description}"
      From this wardrobe, suggest the best outfit matching that aesthetic.
      Return JSON: {"item_ids":[array of ids],"outfit_name":"...","description":"why this matches"}
      Wardrobe:
      #{catalog}
    P
    chat(prompt)
  end

  def enclothed_cognition_tag(item)
    prompt = <<~P
      For this clothing item, suggest the most likely psychological/mood effect when worn.
      Choose one: energising, calming, confident, playful, neutral.
      Also suggest life_phase: current, past-self, or aspirational.
      Reply JSON: {"mood_effect":"...","life_phase":"...","reason":"..."}
      Item: #{item.title}, category: #{item.category}, color: #{item.color}, brand: #{item.brand}
    P
    chat(prompt)
  end

  def embedding_for(item)
    text = item.embedding_text.to_s
    seed = Zlib.crc32(text)
    Array.new(64) do |index|
      (((seed + index * 1_103_515_245) % 10_000) / 10_000.0).round(6)
    end
  end

  private

  def build_client
    token = ENV["OPENROUTER_API_KEY"].to_s.strip
    return nil if token.empty?

    OpenAI::Client.new(access_token: token, uri_base: OPENROUTER_BASE)
  end

  def chat(prompt)
    return fallback_response(prompt) unless @client

    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: [{ role: "user", content: prompt }],
        response_format: { type: "json_object" }
      }
    )
    content = response.dig("choices", 0, "message", "content")
    return fallback_response(prompt) if content.blank?

    JSON.parse(content)
  rescue JSON::ParserError => e
    Rails.logger.warn("WardrobeAI invalid JSON: #{e.message}")
    fallback_response(prompt)
  rescue StandardError => e
    Rails.logger.error("WardrobeAI error: #{e.class}: #{e.message}")
    fallback_response(prompt)
  end

  def fallback_response(prompt)
    if prompt.include?("outfit combinations")
      { "outfits" => [] }
    elsif prompt.include?("matching:")
      { "item_ids" => [], "explanation" => "AI search unavailable" }
    elsif prompt.include?("capsule wardrobe")
      { "items" => [], "gap_items" => [] }
    else
      {}
    end
  end

  def infer_style_profile(answers)
    prompt = <<~PROMPT
      User answered these 5 style profile questions. Infer primary aesthetic as one of: minimal, bold, classic.
      Return JSON only: {"aesthetic": "minimal|bold|classic", "reason": "short", "suggestions": ["item type 1", "item type 2"]}
      Answers: #{answers.inspect}
      Current wardrobe sample: #{ @user.items.limit(3).map { |i| "#{i.title} (#{i.category}, #{i.color})" }.join("; ") }
    PROMPT
    chat(prompt)
  end

  def suggest_packing_list(duration, climate)
    prompt = <<~PROMPT
      Suggest 5-8 outfits from the user's wardrobe for a #{duration}-day trip in #{climate} climate.
      Return JSON: {"outfits": [{"name": "outfit name", "items": ["item title 1", "item title 2"]}, ...], "tips": "brief packing tip"}
      User wardrobe: #{ @user.items.limit(10).map { |i| "#{i.title} (#{i.category}, #{i.color}, #{i.season})" }.join("; ") }
    PROMPT
    chat(prompt)
  end
end
