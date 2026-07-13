# frozen_string_literal: true

module Amber
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
      items = [nav_item("Home", h.root_path, :home, aria: { label: "Home" })]

      if h.authenticated?
        items.concat(
          [
            nav_item("Feed", h.feed_posts_path, :posts, aria: { label: "Feed" }),
            nav_item("Wardrobe", h.items_path, :wardrobe, aria: { label: "Wardrobe" }),
            nav_item("Outfits", h.outfits_path, :outfits, aria: { label: "Outfits" }),
            nav_item("Planner", h.planned_outfits_path, :planner, aria: { label: "Planner" }),
            nav_item("Search", h.ai_search_path, :search_compact, aria: { label: "Search" }),
            nav_item("Messages", h.messages_path, :messages, aria: { label: "Messages" }),
            nav_item(
              "Sign out",
              h.session_path,
              :sign_out,
              aria: { label: "Sign out" },
              data: { turbo_method: :delete, turbo_prefetch: false }
            )
          ]
        )
      else
        items.concat(
          [
            nav_item("Demo", h.demo_wardrobe_path, :demo, aria: { label: "Demo wardrobe" }),
            nav_item("Sign in", h.new_session_path, :sign_in, aria: { label: "Sign in" }),
            nav_item("Sign up", h.new_registration_path, :sign_up, aria: { label: "Sign up" })
          ]
        )
      end

      items
    end

    def tab_bar_items
      h = @helper
      items = [nav_item("Home", h.root_path, :home, aria: { label: "Home" })]

      if h.authenticated?
        items.concat(
          [
            nav_item("Feed", h.feed_posts_path, :posts, aria: { label: "Feed" }),
            nav_item("Wardrobe", h.items_path, :wardrobe, aria: { label: "Wardrobe" }),
            nav_item("Outfits", h.outfits_path, :outfits, aria: { label: "Outfits" })
          ]
        )
      else
        items.concat(
          [
            nav_item("Demo", h.demo_wardrobe_path, :demo, aria: { label: "Demo wardrobe" }),
            nav_item("Sign in", h.new_session_path, :sign_in, aria: { label: "Sign in" })
          ]
        )
      end

      items
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