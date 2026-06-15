# frozen_string_literal: true

class Dating::ProfilesController < Dating::BaseController
  before_action :set_profile, only: %i[show edit update]

  def show; end

  def edit
    @neighborhoods = available_neighborhoods
  end

  def new
    @profile = Current.user.build_dating_profile
    @neighborhoods = available_neighborhoods
  end

  def create
    @profile = Current.user.build_dating_profile(profile_params)
    if @profile.save
      redirect_to(dating_root_path, notice: "Profile created")
    else
      @neighborhoods = available_neighborhoods
      render(:new, status: :unprocessable_entity)
    end
  end

  def update
    if @profile.update(profile_params)
      redirect_to(dating_root_path, notice: "Profile updated")
    else
      @neighborhoods = available_neighborhoods
      render(:edit, status: :unprocessable_entity)
    end
  end

  private

  def set_profile
    @profile = Current.user.dating_profile || redirect_to(new_dating_profile_path)
  end

  def profile_params
    params.require(:dating_profile).permit(:bio, :gender, :looking_for, :age, :location, :latitude, :longitude, :neighborhood_id, :bydel, :visible, photos: [])
  end

  def available_neighborhoods
    city = Current.city || City.find_by(slug: "bergen") || City.first
    city ? city.neighborhoods.order(:name) : Neighborhood.none
  end
end
