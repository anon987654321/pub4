# frozen_string_literal: true

# What amber answers with when there is no model to ask.
#
# OPENROUTER_API_KEY is unset on most machines and on vm23 by default, so these
# are not an edge case — they are what the wardrobe pages render most of the
# time, and `available?` being false has to stay a working product rather than
# an error state. Split out of wardrobe_ai.rb when that file passed its
# file-length ceiling, along the seam that was already there: everything here
# is deterministic Ruby over the user's own items, and everything left in
# WardrobeAi either calls a model or decides whether it can.
#
# Included rather than extracted to an object: these read `user` and the item
# scopes off the instance, and threading those through a collaborator would buy
# indirection and nothing else. They stay private to WardrobeAi.
class WardrobeAi
  module Offline
    private

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
    end
  end
