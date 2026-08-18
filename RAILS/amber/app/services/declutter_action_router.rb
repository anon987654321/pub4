# frozen_string_literal: true

class DeclutterActionRouter
  def initialize(item)
    @item = item
  end

  def action
    score = @item.declutter_score
    recommendation = score[:recommendation]

    {
      recommendation: recommendation,
      destination: destination_for(recommendation),
      copy: copy_for(recommendation),
      score: score,
    }
  end

  private

  def destination_for(recommendation)
    case recommendation
    when "keep" then "active_wardrobe"
    when "wear_this_week" then "challenge"
    when "replace_gradually" then "replacement_watchlist"
    when "repair" then "repair_queue"
    when "sell" then "resale"
    when "donate" then donation_bucket
    when "sentimental_archive" then "memory_box"
    else "declutter_box"
    end
  end

  def donation_bucket
    return "winter_clothing_donation" if @item.category == "Outerwear"
    return "workwear_donation" if @item.occasions.include?("work")
    return "textile_recycling" if @item.lifecycle_state == "repair"

    "general_donation"
  end

  def copy_for(recommendation)
    case recommendation
    when "keep" then "Keep: it still has joy and real utility."
    when "wear_this_week" then "Try once this week before deciding."
    when "replace_gradually" then "Useful but low joy: replace only when a better version appears."
    when "repair" then "Repair before releasing; this may still serve you."
    when "sell" then "Good resale candidate. Photograph and list it while in season."
    when "donate" then "Ready to release through donation."
    when "sentimental_archive" then "Move out of daily wardrobe into a memory archive."
    else "Move to a 30-day declutter box."
    end
  end
end
