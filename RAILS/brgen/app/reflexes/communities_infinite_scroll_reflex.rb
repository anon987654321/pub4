# frozen_string_literal: true

class CommunitiesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "communities/card", as: :community

  private

  def scope
    # The index's own scope: without visible_to, page two listed private
    # communities to people outside them.
    scope = Community.visible_to(Current.user).popular.includes(:user)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("name LIKE ? OR description LIKE ?", term, term)
  end
end
