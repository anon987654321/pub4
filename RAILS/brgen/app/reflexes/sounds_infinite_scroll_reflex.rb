# frozen_string_literal: true

# The sound library. tv's channels, videos and shows have scroll-loaded since
# the reflex spine landed; sounds was added later and got a pager.
class SoundsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "tv/sounds/sound", as: :sound, wrap_in: :li

  private

  def scope = Tv::Sound.popular.includes(:user)
end
