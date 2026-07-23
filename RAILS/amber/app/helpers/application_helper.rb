# frozen_string_literal: true

module ApplicationHelper
  include Pagy::Frontend

  def amber_ai_available?
    WardrobeAi.configured?
  end

  def master_photograph_available?
    WardrobeAi.master_photograph_available?
  end

  def analysis_status_label(status)
    case status.to_s
    when "photo_polish_done" then "Photo polished"
    when "photo_polish_failed" then "Photo polish failed"
    when "photo_polish_skipped", "no_photos" then "No photo polish"
    when "pending" then "Pending media"
    when /segmentation|background/ then "Legacy media status (polish pipeline)"
    else status.to_s.humanize
    end
  end

  def current_creator_profile
    return unless Current.user

    CreatorProfile.find_by(user: Current.user)
  end

  def wardrobe_color_swatch(color)
    case color.to_s.downcase
    when /navy|indigo/ then "#3c4858"
    when /black|charcoal/ then "#3c4043"
    when /white|ivory|oatmeal|cream|pearl/ then "#f8f9fa"
    when /blush|rose|mauve/ then "#f6d6d9"
    when /sage|olive/ then "#c8d5b9"
    when /rust|terracotta/ then "#c96b4b"
    when /camel|tan|gold/ then "#d4a574"
    when /nude/ then "#e8d2c5"
    when /tortoise/ then "#8b5e3c"
    else "#e8eaed"
    end
  end

  def responsive_image_url(attachment, widths: [ 400, 800, 1_200 ])
    return url_for(attachment) unless attachment.respond_to?(:variant)

    widths = Array(widths).map(&:to_i).uniq.sort
    largest = widths.last
    url_for(attachment.variant(resize_to_limit: [ largest, largest ]))
  end
end
