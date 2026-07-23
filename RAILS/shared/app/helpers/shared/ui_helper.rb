# frozen_string_literal: true

module Shared
  # Cross-app x.com UI rendering helpers (icons, nav items, feed tabs).
  module UiHelper
    NavItem = Data.define(:label, :path, :icon, :active, :aria, :data)

    REACTION_GLYPHS = {
      "like" => :like,
      "love" => :like,
      "laugh" => "😂",
      "wow" => "😮",
      "sad" => "😢",
      "angry" => "😠",
      "local" => "📍",
    }.freeze

    def icon(name, size: 18, css_class: nil)
      render(partial: "shared/icon", locals: { name: name.to_sym, size: size, css_class: css_class })
    end

    def reaction_glyph(kind)
      glyph = REACTION_GLYPHS.fetch(kind.to_s, kind.to_s)
      return icon(glyph, size: 18) if glyph.is_a?(Symbol)

      tag.span(glyph, class: "reaction-glyph", aria: { hidden: true })
    end

    def feed_tab(label:, path:, active: false)
      link_to label, path, class: "feed-tab#{" active" if active}"
    end

    def render_sidebar_nav(items)
      safe_join(Array(items).map { |item| sidebar_nav_link(item) })
    end

    def render_tab_bar(items)
      safe_join(Array(items).map { |item| tab_bar_link(item) })
    end

    private

    def sidebar_nav_link(item)
      attrs = nav_item_attrs(item)
      link_options = { class: attrs[:class], aria: attrs[:aria] }
      link_options[:data] = attrs[:data] if attrs[:data].present?
      link_to(attrs[:path], **link_options) do
        safe_join([icon(attrs[:icon], size: 26), tag.span(attrs[:label])])
      end
    end

    def tab_bar_link(item)
      attrs = nav_item_attrs(item)
      link_to(attrs[:path], class: "tab-item", aria: tab_aria(item, attrs)) do
        icon(attrs[:icon], size: 26)
      end
    end

    def nav_item_attrs(item)
      if item.is_a?(NavItem)
        {
          label: item.label,
          path: item.path,
          icon: item.icon,
          class: "nav-item#{" active" if item.active}",
          aria: item.aria || { label: item.label },
          data: item.data
        }
      else
        {
          label: item.fetch(:label),
          path: item.fetch(:path),
          icon: item.fetch(:icon),
          class: "nav-item#{" active" if item[:active]}",
          aria: item[:aria] || { label: item[:label] },
          data: item[:data]
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
