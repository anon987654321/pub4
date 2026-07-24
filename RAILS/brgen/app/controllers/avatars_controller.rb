# frozen_string_literal: true

# BRGEN_OLD's identicon avatars (pub/__OLD_BACKUPS/BRGEN_OLD), ported from
# Quilt::Identicon + RMagick/ImageMagick to Quilt's pure-Ruby SVG backend --
# no native dependency, consistent with this codebase's other image work
# (ruby-vips, not ImageMagick). Deterministic per user id (not email, so it
# can't be reverse-hashed toward a real address) -- same pattern renders
# every time, so it's safe to cache indefinitely.
class AvatarsController < ApplicationController
  def show
    user = User.find(params[:id])
    svg = Quilt::Identicon.new(user.id.to_s, scale: 6, transparent: true, format: "svg").to_blob

    expires_in 1.year, public: true
    render plain: svg, content_type: "image/svg+xml"
  end
end
