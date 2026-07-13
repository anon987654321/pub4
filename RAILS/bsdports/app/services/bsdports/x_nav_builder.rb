# frozen_string_literal: true

module Bsdports
  class XNavBuilder
    def self.sidebar_items(request, helper)
      new(request, helper).sidebar_items
    end

    def self.tab_bar_items(request, helper)
      new(request, helper).tab_bar_items
    end

    def initialize(request, helper)
      @request = request
      @helper = helper
    end

    def sidebar_items
      h = @helper
      items = [
        nav_item("Home", h.root_path, :home, aria: { label: "BSDports home" }),
        nav_item("Ports", h.ports_path, :posts, aria: { label: "Ports" }),
        nav_item("Categories", h.categories_path, :explore, aria: { label: "Categories" }),
        nav_item("Maintainers", h.maintainers_path, :profile, aria: { label: "Maintainers" })
      ]

      if h.authenticated?
        items << nav_item("Inbox", h.notifications_path, :notifications, aria: { label: "Inbox" })
      else
        items << nav_item("Sign in", h.new_session_path, :sign_in, aria: { label: "Sign in" })
      end

      items
    end

    def tab_bar_items
      h = @helper
      items = [
        nav_item("Home", h.root_path, :home, aria: { label: "Home" }),
        nav_item("Ports", h.ports_path, :posts, aria: { label: "Ports" }),
        nav_item("Categories", h.categories_path, :explore, aria: { label: "Categories" }),
        nav_item("Maintainers", h.maintainers_path, :profile, aria: { label: "Maintainers" })
      ]

      if h.authenticated?
        items << nav_item("Inbox", h.notifications_path, :notifications, aria: { label: "Inbox" })
      else
        items << nav_item("Sign in", h.new_session_path, :sign_in, aria: { label: "Sign in" })
      end

      items
    end

    private

    def nav_item(label, path, icon, aria:, active: nil)
      Shared::XUiHelper::NavItem.new(
        label: label,
        path: path,
        icon: icon,
        active: active.nil? ? @helper.current_page?(path) : active,
        aria: aria
      )
    end
  end
end