# frozen_string_literal: true

module Shared
  # Cross-app x.com UI rendering helpers (icons, nav items, feed tabs).
  module XUiHelper
    NavItem = Data.define(:label, :path, :icon, :active, :aria)

    REACTION_GLYPHS = {
      "like" => :like,
      "love" => :like,
      "laugh" => "😂",
      "wow" => "😮",
      "sad" => "😢",
      "angry" => "😠",
      "local" => "📍"
    }.freeze

    def x_icon(name, size: 18)
      render(partial: "shared/x_icon", locals: { name: name.to_sym, size: size })
    end

    def x_reaction_glyph(kind)
      glyph = REACTION_GLYPHS.fetch(kind.to_s, kind.to_s)
      return x_icon(glyph, size: 18) if glyph.is_a?(Symbol)

      tag.span(glyph, class: "x-reaction-glyph", aria: { hidden: true })
    end

    def x_feed_tab(label:, path:, active: false)
      link_to label, path, class: "feed-tab#{" active" if active}"
    end

    def x_render_sidebar_nav(items)
      safe_join(Array(items).map { |item| x_sidebar_nav_link(item) })
    end

    def x_render_tab_bar(items)
      safe_join(Array(items).map { |item| x_tab_bar_link(item) })
    end

    private

    def x_sidebar_nav_link(item)
      attrs = x_nav_item_attrs(item)
      link_to(attrs[:path], class: attrs[:class], aria: attrs[:aria]) do
        safe_join([x_icon(attrs[:icon], size: 26), tag.span(attrs[:label])])
      end
    end

    def x_tab_bar_link(item)
      attrs = x_nav_item_attrs(item)
      link_to(attrs[:path], class: "tab-item", aria: tab_aria(item, attrs)) do
        x_icon(attrs[:icon], size: 26)
      end
    end

    def x_nav_item_attrs(item)
      if item.is_a?(NavItem)
        {
          label: item.label,
          path: item.path,
          icon: item.icon,
          class: "nav-item#{" active" if item.active}",
          aria: item.aria || { label: item.label }
        }
      else
        {
          label: item.fetch(:label),
          path: item.fetch(:path),
          icon: item.fetch(:icon),
          class: "nav-item#{" active" if item[:active]}",
          aria: item[:aria] || { label: item[:label] }
        }
      end
    end

    def tab_aria(item, attrs)
      active = item.is_a?(NavItem) ? item.active : item[:active]
      aria = (attrs[:aria] || {}).dup
      aria[:label] ||= attrs[:label]
      aria[:current] = "page" if active
      aria
    end
  end
end