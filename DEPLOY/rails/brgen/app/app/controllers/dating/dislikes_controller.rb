class Dating::DislikesController < Dating::BaseController
  def create
    user = User.find(params[:user_id])
    Dating::Dislike.find_or_create_by!(disliker: Current.user, dislikee: user)
    redirect_to dating_root_path
  end
end
