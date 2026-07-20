# frozen_string_literal: true

class WebVitalsController < ActionController::API
  def create
    lcp = params[:lcp].presence
    inp = params[:inp].presence
    cls = params[:cls].presence
    path = params[:path].to_s

    return head :bad_request if path.blank? || (lcp.blank? && inp.blank? && cls.blank?)

    Rails.logger.info("web_vitals lcp=#{lcp} inp=#{inp} cls=#{cls} path=#{path}")
    head :no_content
  end
end
