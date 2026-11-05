# frozen_string_literal: true

# BRGEN_OLD's identicon avatars (pub/__OLD_BACKUPS/BRGEN_OLD), ported from
# Quilt::Identicon + RMagick/ImageMagick to Quilt's pure-Ruby SVG backend --
# no native dependency, consistent with this codebase's other image work
# (ruby-vips, not ImageMagick). Deterministic per user id (not email, so it
# can't be reverse-hashed toward a real address) -- same pattern renders
# every time, so it's safe to cache indefinitely.
#
# A person who uploaded a photo (users#edit) gets that instead. Only a public
# profile's photo is served: a departing, deleted or nonexistent id answers
# with the identicon, exactly as an id with no photo does, so the response
# still says nothing about whether an account is leaving.
class AvatarsController < ApplicationController
  def show
    identifier = params[:id].to_s
    return head :not_found unless identifier.match?(/\A\d+\z/)

    expires_in 1.year, public: true
    photo = uploaded_photo(identifier)
    return redirect_to(rails_representation_path(photo.variant(:profile))) if photo

    svg = Quilt::Identicon.new(identifier, scale: 6, transparent: true, format: "svg").to_blob
    render plain: svg, content_type: "image/svg+xml"
  end

  private

  def uploaded_photo(identifier)
    avatar = User.public_profiles.find_by(id: identifier)&.avatar
    avatar if avatar&.attached?
  end
end
