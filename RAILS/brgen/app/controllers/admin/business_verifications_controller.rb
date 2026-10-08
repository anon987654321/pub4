# frozen_string_literal: true

# The queue a person works to decide who shows as a verified business.
class Admin::BusinessVerificationsController < ApplicationController
  include AdminAccess

  before_action :require_admin!

  def index
    @pagy, @verifications = pagy(BusinessVerification.pending.includes(:business, :requested_by).order(:created_at))
  end

  def update
    verification = BusinessVerification.find(params[:id])
    case params[:decision]
    when "approve" then verification.approve!(by: Current.user, note: params[:note])
    when "reject" then verification.reject!(by: Current.user, note: params[:note])
    else return redirect_to(admin_business_verifications_path, alert: t("flash.business_verifications.no_decision"))
    end
    redirect_to admin_business_verifications_path, notice: t("flash.business_verifications.reviewed")
  end
end
