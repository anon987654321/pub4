# frozen_string_literal: true

# Asking to be verified, and — for whoever reviews — answering.
class Dating::VerificationsController < Dating::BaseController
  before_action :require_user_session
  before_action :set_profile, only: %i[new create]

  # The pose is drawn here and carried in the form, so the reviewer knows which
  # gesture was asked for. Drawing it at submit time would let a stale photo be
  # posted against whatever pose came up.
  def new
    @verification = @profile.verifications.new(pose: Dating::Verification.pose_for_request)
  end

  def create
    @verification = @profile.verifications.new(pose: params.require(:verification)[:pose])
    @verification.selfie.attach(params.require(:verification)[:selfie]) if params.dig(:verification, :selfie)
    if @verification.save
      redirect_to profile_path, notice: t("flash.dating.verification_sent")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # The review queue. Reviewed by a person on purpose: face matching fails on
  # exactly the people it should not, and a wrong "not verified" on a dating
  # profile is worse than a slow one.
  def index
    return head :forbidden unless reviewer?

    @verifications = Dating::Verification.pending.includes(profile: :user).order(:created_at)
  end

  def update
    return head :forbidden unless reviewer?

    verification = Dating::Verification.find(params[:id])
    case params[:decision]
    when "approve" then verification.approve!(by: Current.user, note: params[:note])
    when "reject" then verification.reject!(by: Current.user, note: params[:note])
    else return redirect_to(verifications_path, alert: t("flash.dating.verification_no_decision"))
    end
    redirect_to verifications_path, notice: t("flash.dating.verification_reviewed")
  end

  private

  def set_profile
    @profile = current_dating_profile
    redirect_to new_profile_path, alert: t("flash.dating.profile_first") if @profile.blank?
  end

  # The same admin the moderation queue uses. A dating verification is a
  # moderation decision, and inventing a second class of reviewer for it would
  # be a second place to get wrong who may see other people's selfies.
  def reviewer? = Current.user.present? && Current.user.email_address == ENV["BRGEN_ADMIN_EMAIL"]
end
