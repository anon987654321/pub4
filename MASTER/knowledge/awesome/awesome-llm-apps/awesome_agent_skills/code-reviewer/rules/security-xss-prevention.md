# frozen_string_literal: true

require 'action_view'
require 'action_view/helpers/sanitize_helper'

module SecurityHelper
  include ActionView::Helpers::SanitizeHelper

  # Sanitizes user‑generated HTML, permitting only a strict whitelist.
  # Returns a plain‑text empty string for nil or non‑string input.
  #
  # Example:
  #   safe_html('<script>alert(1)</script><b>Bold</b>')
  #   # => "<b>Bold</b>"
  #
  # The whitelist mirrors common safe elements for user‑generated content.
  def safe_html(text)
    return '' if text.nil? || !text.respond_to?(:to_s)

    sanitize(
      text.to_s,
      tags: %w[b i strong em u a img],
      attributes: %w[href src alt title],
      protocols: %w[http https mailto]
    )
  end
end