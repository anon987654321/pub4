# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  private

  def visitor?
    request.env["master.tier"] != "authenticated"
  end
  helper_method :visitor? if respond_to?(:helper_method)

  def container
    Rails.application.config.x.master_container
  end

  def start_ms
    Rails.application.config.x.master_start_ms
  end
end
