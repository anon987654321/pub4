# frozen_string_literal: true

class Dating::RewindsController < Dating::BaseController
  before_action :require_user_session

  def create
    undone = Dating::Dislike.rewind!(Current.user)
    if undone
      redirect_to root_path, notice: t("flash.dating.rewound")
    else
      redirect_to root_path, alert: t("flash.dating.nothing_to_rewind")
    end
  end
end
