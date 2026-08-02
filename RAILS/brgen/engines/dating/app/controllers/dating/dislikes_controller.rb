# frozen_string_literal: true

class Dating::DislikesController < Dating::BaseController
  before_action :require_user_session

  def create
    user = User.find(params[:user_id])
    Dating::Dislike.find_or_create_by!(disliker: Current.user, dislikee: user)
    redirect_to root_path
  end
end
