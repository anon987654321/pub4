# frozen_string_literal: true

# The write side, and the security boundary.
#
# Nothing here trusts the body until the signature over it verifies: an inbox
# that skips that step accepts a Delete for anyone's post and a Follow from
# anyone's account, because the actor field is a string the sender chose.
class Fediverse::InboxesController < ApplicationController
  allow_unauthenticated_access
  # ActivityPub POSTs carry no CSRF token by design — the signature is the
  # authentication, and it is checked below rather than skipped along with this.
  skip_forgery_protection

  # The signature check is the security boundary, and it is not the first thing
  # that happens. `Fediverse::ActorFetcher.for_key_id(signature_key_id)` runs
  # before it, and that is an outbound HTTPS GET to a URL taken straight from the
  # sender's own Signature header — so an unauthenticated POST to this endpoint
  # makes brgen fetch a URL of the sender's choosing, and nothing here limited
  # how often. Verifying the signature first is not available as a fix: the
  # public key needed to verify it is what the fetch goes to get.
  #
  # By IP, and generous, because legitimate federation is bursty — a popular
  # post being boosted arrives as a flood of Create activities from one relay.
  # 300/minute is well above real traffic and far below useful amplification.
  # head :too_many_requests rather than a redirect: every other response on this
  # action is a bare status, and a remote server is reading them, not a person.
  rate_limit to: 300, within: 1.minute, only: :create, with: -> { head :too_many_requests }
  skip_write_throttle

  # A body larger than this is not a real activity. Read before parsing, so a
  # malicious sender cannot make us allocate their way.
  MAX_BODY = Fediverse::InboxBodyLimit::MAX_BYTES

  def create
    body = request.raw_post.to_s
    activity = parse(body)
    return head :bad_request if activity.blank?

    refusal = refusal_before_fetch(body)
    return head refusal if refusal

    actor = Fediverse::ActorFetcher.for_key_id(signature_key_id)
    return head :unauthorized if actor.blank?

    return head :forbidden if FediBlock.blocked?(actor.domain)

    # The signer and the claimed author must be the same account. Without this,
    # a valid signature from any actor authorises an activity attributed to any
    # other — which is the whole game.
    return head :forbidden unless claims_match?(activity, actor)

    unless signed_by?(actor, body)
      actor = Fediverse::ActorFetcher.refetch(actor)
      return head :unauthorized unless actor && signed_by?(actor, body)
    end

    Fediverse::InboxProcessor.new(activity, actor).call
    # 202 rather than 200: the work is queued, and saying "done" for something
    # that has not been delivered yet is the kind of lie that makes debugging
    # federation miserable.
    head :accepted
  end

  private

  def signed_by?(actor, body)
    Fediverse::Signature.verify(request:, body:, public_key_for: ->(_key_id) { actor.public_key })
  end

  def parse(body)
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def signature_key_id
    Fediverse::Signature.parse(request.headers["Signature"])["keyId"]
  end

  # Before the actor is fetched: a blocked instance must not be able to make
  # this one issue an outbound request by POSTing here, and a stale, unsigned
  # or body-swapped POST is refused without brgen fetching a URL the sender
  # chose.
  def refusal_before_fetch(body)
    return :forbidden if FediBlock.blocked_uri?(signature_key_id)

    :unauthorized unless signature_preconditions?(body)
  end

  # Fediverse::Signature.verify repeats these; they run here first because
  # they are free and the actor fetch is not.
  def signature_preconditions?(body)
    covered = Fediverse::Signature.parse(request.headers["Signature"])["headers"].to_s.split(/\s+/)
    (Fediverse::Signature::REQUIRED_COVERAGE - covered).empty? &&
      Fediverse::Signature.fresh?(request.headers["Date"]) &&
      Fediverse::Signature.digest_matches?(request.headers["Digest"], body)
  end

  def claims_match?(activity, actor)
    claimed = activity["actor"]
    claimed = claimed["id"] if claimed.is_a?(Hash)
    claimed.to_s == actor.uri
  end
end
