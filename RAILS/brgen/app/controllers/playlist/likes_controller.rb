# frozen_string_literal: true

class Playlist::LikesController < Playlist::BaseController
  before_action :require_real_user
  before_action :set_set

  def create
    @set.likes.find_or_create_by!(user: Current.user, playlist_id: nil)
    redirect_to playlist_set_path(@set), notice: t("playlist.set_liked", default: "Set liked")
  end

  def destroy
    @set.likes.where(user: Current.user).destroy_all
    redirect_to playlist_set_path(@set), notice: t("playlist.set_unliked", default: "Like removed")
  end

  private

  def set_set
    @set = Playlist::Set.find(params[:set_id])
  end
end