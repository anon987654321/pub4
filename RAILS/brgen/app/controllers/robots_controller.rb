# frozen_string_literal: true

class RobotsController < ApplicationController
  # Rendered per-request (not a static file) because brgen serves many city
  # domains and vertical subdomains — the Sitemap: line must point back at
  # whichever host was actually requested, which a static public/robots.txt
  # cannot do.
  def show
    render plain: <<~ROBOTS, content_type: "text/plain"
      User-agent: *
      Disallow: /conversations
      Disallow: /messages
      Disallow: /admin
      Disallow: /confirm_email/
      Disallow: /location
      Disallow: /nearby
      Disallow: /profile
      Disallow: /likes
      Disallow: /dislikes
      Disallow: /matches
      Disallow: /next
      Disallow: /cart

      Sitemap: #{request.base_url}/sitemap.xml
    ROBOTS
  end
end
