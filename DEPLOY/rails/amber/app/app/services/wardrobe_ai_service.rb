# frozen_string_literal: true

class WardrobeAiService
  OPENROUTER_BASE = "https://openrouter.ai/api/v1"
  MODEL = "google/gemini-2.0-flash-001"

  def initialize(user)
    @user   = user
    @client = OpenAI::Client.new(
      access_token: ENV.fetch("OPENROUTER_API_KEY"),
      uri_base:     OPENROUTER_BASE
    )
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

  private

  def chat(prompt)
    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: [{ role: "user", content: prompt }],
        response_format: { type: "json_object" }
      }
    )
    JSON.parse(response.dig("choices", 0, "message", "content"))
  rescue => e
    Rails.logger.error("WardrobeAI error: #{e.message}")
    {}
  end
end
