# frozen_string_literal: true

module Brgen
  class XNavBuilder
    def self.sidebar_items(request, helper)
      new(request, helper).sidebar_items
    end

    def self.tab_bar_items(request, helper)
      new(request, helper).tab_bar_items
    end

    def self.home_feed_tabs(request, helper)
      new(request, helper).home_feed_tabs
    end

    def initialize(request, helper)
      @request = request
      @helper = helper
    end

    def sidebar_items
      h = @helper
      items = [
        nav_item("Home", h.root_path, :home, aria: { label: "Home" }),
        nav_item("Explore", h.communities_path, :explore, aria: { label: "Explore" }),
        nav_item("Search", h.global_search_path, :search_compact, aria: { label: "Search" }),
        nav_item("Notifications", h.notifications_path, :notifications, aria: { label: "Notifications" }),
        nav_item("Messages", h.conversations_path, :messages, aria: { label: "Messages" }),
        nav_item("Nearby", h.nearby_path, :nearby, aria: { label: "Nearby" })
      ]

      if h.authenticated?
        items << nav_item("Profile", h.user_path(Current.user), :profile, aria: { label: "Profile" })
      else
        items << nav_item("Sign in", h.new_session_path, :sign_in, aria: { label: "Sign in" })
      end

      items
    end

    def tab_bar_items
      h = @helper
      [
        nav_item("Home", h.root_path, :home, aria: { label: "Home" }),
        nav_item("Explore", h.communities_path, :explore, aria: { label: "Explore communities" }),
        nav_item("Posts", h.posts_path, :posts, aria: { label: "Posts" }),
        nav_item("Messages", h.conversations_path, :messages, aria: { label: "Messages" }),
        nav_item("Nearby", h.nearby_path, :nearby, aria: { label: "Nearby" })
      ]
    end

    def home_feed_tabs
      h = @helper
      params = @request.query_parameters
      following = h.home_feed_following?

      [
        { label: "For you", path: h.root_path(params.except("feed")), active: !following },
        { label: "Following", path: h.root_path(params.merge("feed" => "following")), active: following }
      ]
    end

    private

    def nav_item(label, path, icon, aria:, data: nil)
      Shared::XUiHelper::NavItem.new(
        label: label,
        path: path,
        icon: icon,
        active: @helper.current_page?(path),
        aria: aria,
        data: data
      )
    end
  end
end