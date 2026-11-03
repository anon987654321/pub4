# frozen_string_literal: true

# The player a pasted link will become, shown while the post is still being
# written, the way the first brgen previewed links under its compose form.
#
# Only a link a Shared::LinkEmbed provider recognises gets an answer, and the
# one request goes to that provider's oEmbed endpoint: the pasted URL itself is
# never fetched. Answers are cached by the link they name, and the endpoint is
# rate-limited, so typing does not turn into a request per keystroke upstream.
class LinkPreviewsController < ApplicationController
  URL_MAX = 2_048

  allow_unauthenticated_access only: :show if respond_to?(:allow_unauthenticated_access)
  rate_limit to: 30, within: 1.minute, only: :show if respond_to?(:rate_limit)

  def show
    match = Shared::LinkEmbed.find(params[:url].to_s[0, URL_MAX])
    return head :no_content unless match

    stored = Rails.cache.fetch([ "link_preview", match.canonical_url ], expires_in: 12.hours) do
      Shared::LinkEmbed.resolve(match).to_h
    end
    embed = Shared::LinkEmbed::Record.from_stored(stored)
    return head :no_content unless embed&.ok?

    render partial: "shared/link_embed", locals: { embed: }
  end
end
