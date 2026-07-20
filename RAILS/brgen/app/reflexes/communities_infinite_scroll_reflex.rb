# frozen_string_literal: true

class CommunitiesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @communities = pagy(communities_scope, page: page, request:)
    super
  end

  private

  def page_html
    @communities.map { |community| render(partial: "communities/card", locals: { community: }) }.join
  end

  def communities_scope
    scope = Community.popular.includes(:user)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("name LIKE ? OR description LIKE ?", term, term)
  end
end
