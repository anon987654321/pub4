# frozen_string_literal: true

class ShowsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "tv/shows/card", as: :show, wrap_in: :li

  private

  # The card wants the channel alongside the show, so this one overrides
  # row_locals rather than carrying its own page_html.
  def row_locals(record)
    { show: record, channel: shows_channel }
  end

  def scope
    scope = shows_channel ? shows_channel.shows : Tv::Show.all
    scope.published
  end

  def shows_channel
    return @shows_channel if defined?(@shows_channel)

    slug = element.dataset["channelSlug"]
    @shows_channel = slug.present? ? Tv::Channel.find_by!(slug:) : nil
  end
end
