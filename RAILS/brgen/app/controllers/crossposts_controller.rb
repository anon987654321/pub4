# frozen_string_literal: true

# The same post in a second community, with its own comment thread.
class CrosspostsController < ApplicationController
  include Shared::FindableBySlug

  before_action :require_user_session

  def create
    # post_repost_path and friends carry the slug (Sluggable#to_param), and
    # looking one up by id is the trap that discarded every vote cast from a
    # feed card until 2026-08-13.
    source = find_by_slug_or_id(Post.all, params[:post_id])
    community = find_by_slug_or_id(Community.all, params[:community_id])

    # postable_by? is the whole check: it reads bans before privacy, so a
    # community that banned this account cannot be reached through a crosspost
    # either.
    return redirect_to(post_path(source), alert: t("flash.community_not_postable")) unless community.postable_by?(Current.user)

    crosspost = source.build_crosspost(community: community, user: Current.user)
    if crosspost.save
      redirect_to post_path(crosspost), notice: t("flash.crossposted")
    else
      redirect_to post_path(source), alert: crosspost.errors.full_messages.first || t("flash.crosspost_failed")
    end
  end
end
