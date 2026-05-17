class Dating::LikesController < Dating::BaseController
  def create
    user = User.find(params[:user_id])
    Dating::Like.find_or_create_by!(liker: Current.user, likee: user)
    redirect_to dating_root_path
  end
end
