# frozen_string_literal: true

# The write side, and the security boundary.
#
# Nothing here trusts the body until the signature over it verifies: an inbox
# that skips that step accepts a Delete for anyone's post and a Follow from
# anyone's account, because the actor field is just a string the sender chose.
class Fediverse::InboxesController < ApplicationController
  allow_unauthenticated_access
  # ActivityPub POSTs carry no CSRF token by design — the signature is the
  # authentication, and it is checked below rather than skipped along with this.
  skip_forgery_protection

  # A body larger than this is not a real activity. Read before parsing, so a
  # malicious sender cannot make us allocate their way.
  MAX_BODY = 200_000

  def create
    body = request.raw_post.to_s
    return head :content_too_large if body.bytesize > MAX_BODY

    activity = parse(body)
    return head :bad_request if activity.blank?

    actor = Fediverse::ActorFetcher.for_key_id(signature_key_id)
    return head :unauthorized if actor.blank?

    # The signer and the claimed author must be the same account. Without this,
    # a valid signature from any actor authorises an activity attributed to any
    # other — which is the whole game.
    return head :forbidden unless claims_match?(activity, actor)

    verified = Fediverse::Signature.verify(
      request: request,
      body: body,
      public_key_for: ->(_key_id) { actor.public_key }
    )
    return head :unauthorized unless verified

    Fediverse::InboxProcessor.new(activity, actor).call
    # 202 rather than 200: the work is queued, and saying "done" for something
    # that has not been delivered yet is the kind of lie that makes debugging
    # federation miserable.
    head :accepted
  end

  private

  def parse(body)
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def signature_key_id
    Fediverse::Signature.parse(request.headers["Signature"])["keyId"]
  end

  def claims_match?(activity, actor)
    claimed = activity["actor"]
    claimed = claimed["id"] if claimed.is_a?(Hash)
    claimed.to_s == actor.uri
  end
end
