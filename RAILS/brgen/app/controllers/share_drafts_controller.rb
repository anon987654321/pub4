# frozen_string_literal: true

class ShareDraftsController < ApplicationController
  rate_limit to: 12, within: 1.minute, only: :publish, name: "share-draft-publish-burst",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  rate_limit to: 30, within: 3.minutes, only: :publish, name: "share-draft-publish-sustained",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip },
             with: -> { redirect_to posts_path, alert: t("shared.flash.rate_limited") }

  before_action :require_real_user
  before_action :require_verified_email
  before_action :set_share_draft, only: %i[show publish destroy]

  def show
    load_communities
  end

  def publish
    load_communities
    attributes = params.require(:post).permit(:title, :content, :community_id, :anonymous)
    community_id = attributes[:community_id].to_s
    @community = @communities.find_by(id: community_id) if community_id.present?

    if community_id.present? && @community.nil?
      redirect_to share_draft_path(@share_draft),
                  alert: t("flash.draft_failed", default: "Choose a community in this city.")
      return
    end

    if @community && !@community.postable_by?(Current.user)
      redirect_to share_draft_path(@share_draft),
                  alert: t("flash.community.members_only", default: "You cannot post in that community.")
      return
    end

    quota = Shared::AnonymousPost.new(request: request, user: Current.user)
    unless quota.allowed?
      redirect_to posts_path, alert: t("flash.anonymous_post_limit", limit: Shared::AnonymousPost::LIMIT)
      return
    end

    title = attributes[:title].to_s.strip
    content = attributes[:content].to_s
    if content.present?
      plain = ActionController::Base.helpers.strip_tags(content).squish
      title = plain.truncate(300) if title.blank? || title.match?(/<[^>]+>/)
    end
    @post = Post.new(
      title: title,
      content: content,
      community: @community,
      user: Current.user,
      city: @share_draft.city,
      # An absent checkbox casts to nil, and posts.anonymous is NOT NULL.
      anonymous: ActiveModel::Type::Boolean.new.cast(attributes[:anonymous]) || false,
    )
    image_blobs = @share_draft.images.blobs
    @post.image.attach(image_blobs.first) if image_blobs.any?
    @post.images.attach(image_blobs.drop(1)) if image_blobs.size > 1
    @post.video.attach(@share_draft.video.blob) if @share_draft.video.attached?

    verdict = PostModeration.new(@post).decide
    unless verdict.approved
      key = verdict.reason == :unverified_author_spam_signals ? "flash.link_requires_verified_account" : "flash.post_blocked_by_moderation"
      redirect_to share_draft_path(@share_draft),
                  alert: t(key, default: "This post could not be published. Review its content and try again.")
      return
    end

    if @post.save
      quota.record_post!
      @share_draft.destroy!
      redirect_to @post, notice: t("flash.posted")
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @share_draft.destroy!
    redirect_to posts_path, notice: t("post.share_draft_discarded", default: "Draft discarded.")
  end

  private

  def set_share_draft
    city = Current.city_record
    raise ActiveRecord::RecordNotFound unless city && Current.user

    @share_draft = ShareDraft.with_attached_images.with_attached_video.includes(:city)
                              .where(user_id: Current.user.id, city_id: city.id)
                              .find(params[:id])
    if @share_draft.expires_at <= Time.current
      @share_draft.destroy!
      raise ActiveRecord::RecordNotFound
    end
  end

  def load_communities
    @communities = Community.where(city_id: @share_draft.city_id, archived_at: nil).order(:name)
  end
end
