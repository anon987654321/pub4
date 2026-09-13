# frozen_string_literal: true

class Dating::ProfilesController < Dating::BaseController
  include Shared::MediaGuard

  before_action :require_user_session
  # Joining is Vipps-only. Everything else on this vertical stays readable to a
  # signed-in person; what a verified identity buys is the right to appear in
  # front of strangers, which is the exact thing a throwaway account is used
  # for. The comment that stood here said "soft guest profiles allowed — no
  # signup to start dating", which this deliberately reverses.
  before_action :require_vipps_identity, only: %i[new create edit update]
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
    if assign_photos && @profile.save
      enqueue_photo_processing
      redirect_to(root_path, notice: t("flash.dating.profile_created"))
    else
      @neighborhoods = available_neighborhoods
      render(:new, status: :unprocessable_entity)
    end
  end

  def update
    @profile.assign_attributes(profile_params)
    if assign_photos && @profile.save
      enqueue_photo_processing
      redirect_to(root_path, notice: t("flash.dating.profile_updated"))
    else
      @neighborhoods = available_neighborhoods
      render(:edit, status: :unprocessable_entity)
    end
  end

  private

  def set_profile
    @profile = Dating::Profile.includes(:user, :neighborhood, photos_attachments: :blob).find_by(user_id: Current.user.id) ||
               redirect_to(new_profile_path)
  end

  def profile_params
    params.require(:profile).permit(:bio, :gender, :looking_for, :age, :location, :neighborhood_id, :bydel, :visible)
  end

  # Photos stay out of profile_params because assigning a has_many_attached
  # replaces the whole set: the empty value a multiple file field always posts
  # would wipe every photo, and one new upload would drop the rest. The set is
  # rebuilt here as the photos kept plus the uploads accepted, and saved with the
  # rest of the profile, so a failed save purges nothing.
  def assign_photos
    removed_ids = Array(params.dig(:profile, :remove_photo_ids)).map(&:to_i)
    uploads = Array(params.dig(:profile, :photos)).compact_blank
    accepted = uploads.filter_map { |upload| accepted_photo(upload) }
    if accepted.size < uploads.size
      @profile.errors.add(:photos, :invalid)
      return false
    end
    return true if removed_ids.empty? && accepted.empty?

    kept = @profile.photos_attachments.includes(:blob).reject { |attachment| removed_ids.include?(attachment.id) }
    @profile.photos = kept.map(&:blob) + accepted
    true
  end

  # A direct upload arrives as a signed blob id and a plain form post as a file;
  # MediaGuard's type and size limits hold for both.
  def accepted_photo(upload)
    return (upload if validate_media_upload(upload) == :ok) if upload.respond_to?(:read)

    blob = ActiveStorage::Blob.find_signed(upload.to_s)
    return nil unless blob
    return nil unless MEDIA_ALLOWED_TYPES.include?(blob.content_type.to_s.downcase)
    return nil if blob.byte_size > MEDIA_MAX_BYTES

    blob
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
