# frozen_string_literal: true
# AN212: GDPR account deletion + export

class AccountSettingsController < ::ApplicationController
  include Shared::AccountDeletion

  before_action :require_user_session

  def show
    @user = Current.user
  end

  def export
    csv = Shared::AccountExporter.new(Current.user).to_csv
    send_data csv, filename: "account-export-#{Current.user.id}.csv", type: "text/csv"
  end

  def destroy
    schedule_account_deletion(Current.user)
    complete_logout_for(Current.user)
    redirect_to root_path, notice: "Account scheduled for deletion in 30 days. Export emailed if configured."
  end

  def cancel_deletion
    cancel_account_deletion(Current.user)
    redirect_to account_path, notice: "Account deletion cancelled"
  end
end