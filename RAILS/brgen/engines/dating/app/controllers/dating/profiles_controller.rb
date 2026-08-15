# frozen_string_literal: true

class Dating::ProfilesController < Dating::BaseController
  # Soft guest profiles allowed — no signup to start dating.
  before_action :require_user_session
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
      enqueue_photo_processing
      redirect_to(root_path, notice: t("flash.dating.profile_created"))
    else
      @neighborhoods = available_neighborhoods
      render(:new, status: :unprocessable_entity)
    end
  end

  def update
    purge_removed_photos
    if @profile.update(profile_params)
      enqueue_photo_processing
      redirect_to(root_path, notice: t("flash.dating.profile_updated"))
    else
      @neighborhoods = available_neighborhoods
      render(:edit, status: :unprocessable_entity)
    end
  end

  private

  def set_profile
    @profile = Dating::Profile.find_by(user_id: Current.user.id) || redirect_to(new_profile_path)
  end

  def profile_params
    params.require(:dating_profile).permit(:bio, :gender, :looking_for, :age, :location, :neighborhood_id, :bydel, :visible, photos: [])
  end

  def purge_removed_photos
    ids = Array(params.dig(:dating_profile, :remove_photo_ids)).map(&:to_i).uniq
    return if ids.empty?

    @profile.photos.where(id: ids).find_each(&:purge)
  end

  def enqueue_photo_processing
    Dating::ProfileMediaJob.perform_later(@profile.id) if @profile.photos.attached?
  end

  def available_neighborhoods
    # City is always resolved automatically from the request domain/TLD before we reach here.
    city = Current.city_record || City.find_by(domain: Current.domain) || City.first
    city ? city.neighborhoods.order(:name) : Neighborhood.none
  end
end
