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
end
