# frozen_string_literal: true

class ChannelsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @channels = pagy(channels_scope, page: page, request:)
    super
  end

  private

  def page_html
    @channels.map do |channel|
      render(partial: "tv/channels/row", locals: { channel: })
    end.join
  end

  def channels_scope
    scope = Tv::Channel.all.includes(:user)
    if element.dataset["q"].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
      channel_ids = scope.where("name LIKE ? OR description LIKE ?", term, term).pluck(:id)
      video_ids = Tv::Video.published.where("title LIKE ? OR description LIKE ?", term, term).pluck(:tv_channel_id)
      scope = scope.where(id: (channel_ids + video_ids).uniq)
    else
      scope = scope.popular
    end
    scope
  end
end