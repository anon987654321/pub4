class Dating::ProfilesController < Dating::BaseController
  before_action :set_profile, only: %i[show edit update]

  def show; end
  def edit; end

  def new
    @profile = Current.user.build_dating_profile
  end

  def create
    @profile = Current.user.build_dating_profile(profile_params)
    @profile.save ?
      redirect_to(dating_root_path, notice: "Profile created") :
      render(:new, status: :unprocessable_entity)
  end

  def update
    @profile.update(profile_params) ?
      redirect_to(dating_root_path, notice: "Profile updated") :
      render(:edit, status: :unprocessable_entity)
  end

  private
  def set_profile    = (@profile = Current.user.dating_profile || redirect_to(new_dating_profile_path))
  def profile_params = params.require(:dating_profile).permit(:bio, :gender, :looking_for, :age, :location, :latitude, :longitude, :visible, photos: [])
end
