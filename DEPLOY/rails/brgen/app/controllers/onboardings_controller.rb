# frozen_string_literal: true

class OnboardingsController < ApplicationController
  before_action :require_real_user
  before_action :redirect_if_complete, only: :show

  INTERESTS = %w[food music tech sports news art nightlife family].freeze
  VERTICALS = %w[core dating marketplace tv playlist takeaway maps].freeze

  def show
    @step = (params[:step] || session[:onboarding_step] || 1).to_i.clamp(1, 3)
    session[:onboarding_step] = @step
    @cities = Brgen::DomainRegistry::ENTRIES.map { |e| [e.city, e.domain] }.uniq.sort_by(&:first)
    @interests = INTERESTS
    @verticals = VERTICALS
    @selected_interests = session[:onboarding_interests] || Current.user.onboarding_interests || []
    @selected_verticals = session[:onboarding_verticals] || Current.user.onboarding_verticals || []
    @selected_city = session[:onboarding_city_slug] || Current.user.onboarding_city_slug
  end

  def update
    step = params[:step].to_i

    case step
    when 1
      session[:onboarding_city_slug] = params[:city_domain]
    when 2
      session[:onboarding_interests] = Array(params[:interests]).map(&:to_s).uniq
    when 3
      session[:onboarding_verticals] = Array(params[:verticals]).map(&:to_s).uniq
      Current.user.update!(
        onboarding_city_slug: session[:onboarding_city_slug],
        onboarding_interests: session[:onboarding_interests] || [],
        onboarding_verticals: session[:onboarding_verticals] || [],
        onboarding_completed_at: Time.current
      )
      session.delete(:onboarding_step)
      session.delete(:onboarding_city_slug)
      session.delete(:onboarding_interests)
      session.delete(:onboarding_verticals)
      redirect_to root_path, notice: "Welcome to your personalized feed."
      return
    end

    redirect_to onboarding_path(step: step + 1)
  end

  private

  def redirect_if_complete
    redirect_to root_path if Current.user.onboarding_completed_at.present? && params[:step].blank?
  end
end