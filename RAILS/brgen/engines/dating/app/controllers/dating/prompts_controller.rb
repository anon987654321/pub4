# frozen_string_literal: true

class Dating::PromptsController < Dating::BaseController
  before_action :require_user_session
  before_action :set_profile

  def create
    prompt = @profile.prompts.new(prompt_params)
    if prompt.save
      redirect_back fallback_location: edit_profile_path, notice: t("flash.dating.prompt_saved")
    else
      redirect_back fallback_location: edit_profile_path, alert: prompt.errors.full_messages.to_sentence
    end
  end

  def destroy
    @profile.prompts.find(params[:id]).destroy
    redirect_back fallback_location: edit_profile_path, notice: t("flash.dating.prompt_removed")
  end

  private

  # Your own profile only. Scoping through the current user rather than reading
  # a profile id from the request is what stops someone answering a prompt on
  # somebody else's profile.
  def set_profile
    @profile = Dating::Profile.find_by(user_id: Current.user.id)
    redirect_to new_profile_path unless @profile
  end

  def prompt_params
    params.require(:dating_prompt).permit(:question, :answer, :position)
  end
end
