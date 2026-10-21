# frozen_string_literal: true

class PrivacySettingsController < ApplicationController
  before_action :require_real_user
  before_action :load_privacy_setting

  def show
  end

  def update
    if @privacy_setting.update(privacy_setting_params)
      redirect_to privacy_setting_path, notice: t("privacy_settings.saved")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_privacy_setting
    @privacy_setting = PrivacySetting.find_or_create_by!(user_id: Current.user.id)
  end

  def privacy_setting_params
    params.require(:privacy_setting).permit(:allow_ai_analysis)
  end
end
