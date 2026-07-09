# frozen_string_literal: true

class ComicStripsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @comic_strips = pagy(comic_strips_scope, page: page, request:)
    super
  end

  private

  def page_html
    @comic_strips.map { |comic_strip| render(partial: "comic_strips/row", locals: { comic_strip: }) }.join
  end

  def comic_strips_scope
    scope = ComicStrip.includes(:user).order(created_at: :desc)
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    scope.where("prompt LIKE :q OR style LIKE :q OR status LIKE :q", q: term)
  end
end