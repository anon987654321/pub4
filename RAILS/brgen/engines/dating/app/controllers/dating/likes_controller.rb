# frozen_string_literal: true

class Dating::LikesController < Dating::BaseController
  before_action :require_user_session

  def create
    user = User.find(params[:user_id])
    like = Dating::Like.find_or_create_by!(liker: Current.user, likee: user)

    redirect_to root_path
  end
end
