# frozen_string_literal: true

module ApplicationHelper
  def sidebar_nav_items
    Bsdports::XNavBuilder.sidebar_items(request, self)
  end

  def tab_bar_items
    Bsdports::XNavBuilder.tab_bar_items(request, self)
  end
end