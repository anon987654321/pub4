# frozen_string_literal: true

class Dating::MatchesController < Dating::BaseController
  before_action :require_user_session

  def index
    @pagy, @matches = pagy(
      Dating::Match.active
        .where("initiator_id = ? OR receiver_id = ?", Current.user.id, Current.user.id)
        .includes(
          initiator: { dating_profile: { photos_attachments: :blob } },
          receiver: { dating_profile: { photos_attachments: :blob } }
        )
    )
  end

  def destroy
    @match = Dating::Match.active
      .where("initiator_id = ? OR receiver_id = ?", Current.user.id, Current.user.id)
      .find(params[:id])
    @match.unmatch!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to matches_path }
    end
  end
end
