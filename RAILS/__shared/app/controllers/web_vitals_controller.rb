# frozen_string_literal: true

class WebVitalsController < ActionController::API
  include Shared::WriteThrottle

  # The beacon's inp_target is a selector the browser built from the DOM, so it
  # is reduced to selector characters before it reaches the log line.
  TARGET_UNSAFE = /[^\w.#\-\[\]=:]/

  def create
    lcp = params[:lcp].presence
    inp = params[:inp].presence
    cls = params[:cls].presence
    path = params[:path].to_s
    inp_target = params[:inp_target].to_s.gsub(TARGET_UNSAFE, "")[0, 120]

    return head :bad_request if path.blank? || (lcp.blank? && inp.blank? && cls.blank?)

    Rails.logger.info("web_vitals lcp=#{lcp} inp=#{inp} cls=#{cls} inp_target=#{inp_target.presence || '-'} path=#{path}")
    head :no_content
  end
end
