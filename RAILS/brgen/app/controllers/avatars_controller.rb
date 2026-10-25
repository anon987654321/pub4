# frozen_string_literal: true

# BRGEN_OLD's identicon avatars (pub/__OLD_BACKUPS/BRGEN_OLD), ported from
# Quilt::Identicon + RMagick/ImageMagick to Quilt's pure-Ruby SVG backend --
# no native dependency, consistent with this codebase's other image work
# (ruby-vips, not ImageMagick). Deterministic per user id (not email, so it
# can't be reverse-hashed toward a real address) -- same pattern renders
# every time, so it's safe to cache indefinitely.
class AvatarsController < ApplicationController
  def show
    # The avatar is a deterministic identicon of the public numeric ID, not a
    # stored personal image. Generate it without consulting account state: a
    # deleted or nonexistent ID must not have a distinguishable response.
    identifier = params[:id].to_s
    return head :not_found unless identifier.match?(/\A\d+\z/)

    svg = Quilt::Identicon.new(identifier, scale: 6, transparent: true, format: "svg").to_blob

    expires_in 1.year, public: true
    render plain: svg, content_type: "image/svg+xml"
  end
end
