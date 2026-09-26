# frozen_string_literal: true

class Dating::DislikesController < Dating::BaseController
  before_action :require_user_session

  def create
    user = Dating::Profile.visible.includes(:user).find_by!(user_id: params[:user_id]).user
    Dating::Dislike.find_or_create_by!(disliker: Current.user, dislikee: user)
    redirect_to root_path
  end
end
