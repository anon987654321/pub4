# frozen_string_literal: true

class ShowsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @shows = pagy(shows_scope, page: page, request:)
    super
  end

  private

  def page_html
    @shows.map { |show| render(partial: "tv/shows/card", locals: { show:, channel: shows_channel }) }.join
  end

  def shows_scope
    scope = shows_channel ? shows_channel.shows : Tv::Show.all
    scope.published
  end

  def shows_channel
    return @shows_channel if defined?(@shows_channel)

    slug = element.dataset["channelSlug"]
    @shows_channel = slug.present? ? Tv::Channel.find_by!(slug:) : nil
  end
end
