# frozen_string_literal: true

# The read side: actor documents, outbox, followers.
#
# Resolved against the requested host, because each city is a separate origin —
# answering brgen.no's @kari on oshlo.no would hand a stranger's posts to
# whoever asked the wrong city.
class Fediverse::ActorsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection
  before_action :set_user

  CONTENT_TYPE = "application/activity+json"

  def show
    render json: Fediverse::Serializer.actor(@user), content_type: CONTENT_TYPE
  end

  def outbox
    # Public posts only, and never a removed one: an outbox is the thing
    # crawlers and relays read, so anything a moderator took down must not be
    # served back out of it.
    posts = Post.kept.where(user_id: @user.id, community_id: nil)
                .order(created_at: :desc).limit(40)
    render json: Fediverse::Serializer.outbox(@user, posts), content_type: CONTENT_TYPE
  end

  def followers
    render json: Fediverse::Serializer.followers(@user, @user.fedi_follows.accepted.count),
           content_type: CONTENT_TYPE
  end

  private

  def set_user
    city = City.find_by(domain: request.host)
    @user = city && User.find_by(username: params[:username], city_id: city.id)
    head :not_found unless @user&.federated?
  end
end
