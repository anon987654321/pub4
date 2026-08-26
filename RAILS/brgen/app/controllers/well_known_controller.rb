# frozen_string_literal: true

# WebFinger and NodeInfo — how the rest of the fediverse discovers that
# @kari@brgen.no is a thing and what speaks for it.
#
# The account is resolved against the *requested host*, because each city is a
# separate origin with its own population: @kari@brgen.no and @kari@oshlo.no are
# different accounts, and answering for the wrong one would hand a stranger's
# posts to anyone who asked the wrong city.
class WellKnownController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  def webfinger
    resource = params[:resource].to_s
    username = resource[/\Aacct:([^@]+)@(.+)\z/, 1]
    domain = resource[/\Aacct:([^@]+)@(.+)\z/, 2]

    if username.blank? || domain.blank? || domain != request.host
      head :not_found
      return
    end

    user = federated_user(username, domain)
    return head :not_found unless user

    render json: {
      subject: "acct:#{username}@#{domain}",
      aliases: [ user.actor_uri ],
      links: [
        { rel: "self", type: "application/activity+json", href: user.actor_uri },
        { rel: "http://webfinger.net/rel/profile-page", type: "text/html", href: user.actor_uri }
      ]
    }, content_type: "application/jrd+json"
  end

  def nodeinfo_index
    render json: {
      links: [
        { rel: "http://nodeinfo.diaspora.software/ns/schema/2.1",
          href: "https://#{request.host}/nodeinfo/2.1" }
      ]
    }
  end

  def nodeinfo
    city = City.find_by(domain: request.host)
    render json: {
      version: "2.1",
      software: { name: "brgen", version: Rails.application.config.x.brgen_version.presence || "0", repository: "https://github.com/anon987654321/pub4" },
      protocols: [ "activitypub" ],
      services: { inbound: [], outbound: [] },
      openRegistrations: true,
      usage: { users: { total: federated_scope(city).count } },
      # A city is an instance. Saying so is the honest description of what this
      # server is, and it is what makes the city partitioning legible to peers.
      metadata: { nodeName: city&.name || "brgen", nodeDescription: "A city." }
    }
  end

  private

  def federated_user(username, domain)
    city = City.find_by(domain: domain)
    return nil if city.blank?

    user = User.find_by(username: username, city_id: city.id)
    user&.federated? ? user : nil
  end

  def federated_scope(city)
    scope = User.where(guest: false).where.not(username: [ nil, "" ])
    city ? scope.where(city_id: city.id) : scope
  end
end
