# frozen_string_literal: true

class CreatorProfilesController < ApplicationController
  before_action :require_real_user, only: %i[new create edit update]
  before_action :set_own_profile, only: %i[edit update]
  before_action :set_public_profile, only: :show

  def show
    policy = WardrobeVisibilityPolicy.new(viewer: Current.user, owner: @profile.user)
    unless @profile.public? || (authenticated? && Current.user == @profile.user)
      return redirect_to root_path, alert: t("flash.creator_profile_private")
    end

    @showcase_items = @profile.creator_wardrobe_items.includes(item: { photos_attachments: :blob }).order(:position)
    @can_remix = policy.can_remix_creator_wardrobe?
  end

  def new
    redirect_to(edit_my_creator_profile_path) if CreatorProfile.exists?(user: Current.user)
    @profile = Current.user.build_creator_profile(
      display_name: Current.user.profile&.display_name.presence || Current.user.email_address.split("@").first,
      handle: default_handle
    )
  end

  def create
    user = User.includes(:creator_profile).find(Current.user.id)
    @profile = user.build_creator_profile(creator_profile_params)
    if @profile.save
      redirect_to creator_profile_path(@profile.handle), notice: t("flash.creator_profile_published")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    return render :edit, status: :unprocessable_entity unless @profile.update(creator_profile_params)

    redirect_to creator_profile_path(@profile.handle), notice: t("flash.creator_profile_updated")
  end

  private

  def set_own_profile
    @profile = CreatorProfile.find_by(user: Current.user) || redirect_to(new_my_creator_profile_path)
  end

  def set_public_profile
    @profile = CreatorProfile.includes(user: :privacy_setting).find_by!(handle: params[:handle])
  end

  def creator_profile_params
    params.require(:creator_profile).permit(:handle, :display_name, :bio, :public)
  end

  def default_handle
    base = Current.user.email_address.to_s.split("@").first.parameterize(separator: "_")
    candidate = base
    suffix = 1
    while CreatorProfile.exists?(handle: candidate)
      candidate = "#{base}_#{suffix}"
      suffix += 1
    end
    candidate
  end
end
