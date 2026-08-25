# frozen_string_literal: true

require "zlib"
require "base64"

class WardrobeAi
  MODEL = "google/gemini-2.0-flash-001"

  # The only part of this service that knows a vendor exists.
  #
  # WardrobeAi used to hold an OpenAI::Client directly, so `chat` reached into
  # `response.dig("choices", 0, "message", "content")` — the service's entire
  # knowledge of AI was one vendor's HTTP response shape, and the test double
  # existed to reproduce that shape rather than the behaviour. The seam is now
  # `ask(prompt) -> String`, which is what the caller actually wants, and the
  # double is three lines.
  #
  # ruby_llm rather than ruby-openai because brgen already uses ruby_llm and
  # two LLM clients in one repo is one more than the number of them anybody
  # keeps current. It speaks OpenRouter natively — openrouter_api_key is a
  # first-class setting, so the uri_base override this used to need is gone.
  class OpenRouter
    def initialize(token)
      @token = token
    end

    # assume_model_exists: the model id is OpenRouter's, not one from
    # ruby_llm's bundled registry, and the registry is a snapshot that goes
    # stale. Refusing to call a model because a shipped list has not heard of
    # it is the wrong failure.
    def ask(prompt)
      RubyLLM.context { |config| config.openrouter_api_key = @token }
             .chat(model: MODEL, provider: :openrouter, assume_model_exists: true)
             .with_params(response_format: { type: "json_object" })
             .ask(prompt)
             .content
    end
  end

  def self.configured?
    ENV["OPENROUTER_API_KEY"].to_s.strip.present?
  end

  def self.master_photograph_available?
    return false if ENV["CI"] == "1" || Rails.env.test?
    return false unless ENV["AMBER_ENABLE_MASTER_PHOTO"].to_s == "1"

    File.directory?(Rails.root.join("..", "..", "MASTER"))
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
    outfits = if vision_items.any?
      images = vision_items.map { |i| image_data_url(i.photos.first) }.compact
      chat_with_vision(prompt, images)["outfits"] || []
    else
      chat(prompt)["outfits"] || []
    end
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
    token = ENV["OPENROUTER_API_KEY"].to_s.strip
    return nil if token.empty?

    OpenRouter.new(token)
  end

  def chat(prompt)
    return fallback_response(prompt) unless @client

    content = @client.ask(prompt)
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
      { "item_ids" => [], "explanation" => "AI search unavailable — using local match when possible" }
    elsif prompt.include?("capsule wardrobe")
      { "items" => [], "gap_items" => [] }
    else
      {}
    end
  end

  def heuristic_joy(item)
    worn = item.times_worn.to_i
    joy = if item.spark_joy == true
      true
    elsif item.spark_joy == false
      false
    else
      worn >= 3 || item.life_phase == "current"
    end
    {
      "sparks_joy" => joy,
      "reason" => joy ? "Worn enough or tagged current-self — treat as a keeper until you feel otherwise." : "Low wear signal and no joy mark — try once more or release.",
      "suggestion" => joy ? "Keep in active wardrobe and log wears." : "Start a wear-this-week challenge or open declutter review.",
      "source" => "heuristic"
    }
  end

  def offline_capsule
    built = CapsuleBuilder.new(@user).build
    explained = CapsuleBuilder.new(@user).explain(built)
    keep_ids = built.map(&:id)
    items = @user.items.active_wardrobe.map do |item|
      decision = if keep_ids.include?(item.id)
        "keep"
      elsif item.spark_joy == false || item.underused?
        "consider"
      else
        "keep"
      end
      reason = explained.find { |row| row[:id] == item.id }&.dig(:reason) || "Outside primary capsule set."
      { "id" => item.id, "title" => item.title, "decision" => decision, "reason" => reason }
    end
    gaps = WardrobeGap.new(@user).gaps.map { |g|
      g[:reason].presence || "#{g[:missing]} more #{g[:category]}"
    }
    { "items" => items, "gap_items" => gaps, "source" => "capsule_builder" }
  end

  def offline_palette
    colors = @user.items.where.not(color: [ nil, "" ]).pluck(:color)
    {
      "palette" => colors.first(6).join(", ").presence || "unknown",
      "season_type" => "unclassified",
      "harmonious" => colors.first(5),
      "clashing" => [],
      "suggestions" => [ "Enable OpenRouter for seasonal colour analysis.", "Add hex/color tags when uploading photos." ],
      "source" => "heuristic"
    }
  end

  def offline_search(query)
    q = query.to_s.strip.downcase
    return { "item_ids" => [], "explanation" => "Empty query", "source" => "heuristic" } if q.blank?

    tokens = q.split(/\s+/).reject(&:blank?)
    matched = @user.items.select do |item|
      hay = [ item.title, item.category, item.color, item.brand, item.material, item.occasion_tags, item.season ].join(" ").downcase
      tokens.any? { |t| hay.include?(t) }
    end
    {
      "item_ids" => matched.map(&:id),
      "explanation" => "Local keyword match (#{matched.size} items). OpenRouter improves natural language.",
      "source" => "heuristic"
    }
  end

  def rule_based_outfits(items, occasion: nil, season: nil)
    return [] if items.blank?

    grouped = items.group_by(&:category)
    picks = [
      grouped["Tops"]&.first || grouped["Dresses"]&.first,
      grouped["Bottoms"]&.first,
      grouped["Shoes"]&.first
    ].compact
    return [] if picks.size < 2

    [ {
      "name" => [ occasion, season, "Closet combo" ].compact_blank.join(" · "),
      "items" => picks.map(&:title),
      "description" => "Rule-based from your active wardrobe (AI key not configured or model returned empty).",
      "source" => "rule"
    } ]
  end

  def image_data_url(photo)
    return nil unless photo

    data = photo.download
    "data:#{photo.content_type.presence || "image/jpeg"};base64,#{Base64.strict_encode64(data)}"
  end

  def chat_with_vision(prompt, image_data_urls)
    return fallback_response(prompt) unless @client && image_data_urls.any?

    content = [ { type: "text", text: prompt } ]
    image_data_urls.each do |url|
      content << { type: "image_url", image_url: { url: url } }
    end

    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: [ { role: "user", content: content } ],
        response_format: { type: "json_object" }
      }
    )
    content_text = response.dig("choices", 0, "message", "content")
    return fallback_response(prompt) if content_text.blank?

    JSON.parse(content_text)
  rescue StandardError => e
    Rails.logger.error("WardrobeAI vision error: #{e.class}: #{e.message}")
    fallback_response(prompt)
  end
end
