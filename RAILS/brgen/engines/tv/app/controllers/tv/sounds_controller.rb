# frozen_string_literal: true

# The clips built on one piece of audio.
class Tv::SoundsController < Tv::BaseController
  allow_unauthenticated_access only: %i[index show]

  def index
    @pagy, @sounds = pagy(Tv::Sound.popular.includes(:user))
  end

  def show
    @sound = Tv::Sound.includes(:user).find(params[:id])
    # Watch time, not view count: the feed ranks that way because views_count is
    # incremented on page load and counts accidental clicks.
    @pagy, @videos = pagy(@sound.videos_by_watch_time.includes(:channel, :user))
  end
end
