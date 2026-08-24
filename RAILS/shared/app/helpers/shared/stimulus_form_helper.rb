# frozen_string_literal: true

module Shared
  module StimulusFormHelper
    # @stimulus-components/character-counter — countdown mode with maxlength.
    def character_counter_field(form, method, max:, autogrow: false, **options)
      rows = options.delete(:rows)
      wrapper = tag.div(
        data: {
          controller: [ "character-counter", ("textarea-autogrow" if autogrow) ].compact.join(" "),
          character_counter_countdown_value: true,
        },
      ) do
        field_options = options.deep_dup
        field_options[:maxlength] = max
        field_options[:data] = (field_options[:data] || {}).merge(character_counter_target: "input")
        field_options[:data][:controller] = "textarea-autogrow" if autogrow

        field =
          if rows
            form.text_area(method, **field_options, rows:)
          else
            form.text_area(method, **field_options)
          end

        safe_join([
          field,
          tag.span(class: "char-counter", data: { character_counter_target: "counter" }, aria: { live: "polite" }),
        ])
      end
      wrapper
    end

    # @stimulus-components/password-visibility
    def password_visibility_field(form, method, **options)
      opts = options.deep_dup
      opts[:data] = (opts[:data] || {}).merge(password_visibility_target: "input")
      opts[:spellcheck] = false unless opts.key?(:spellcheck)

      tag.div(data: { controller: "password-visibility" }, class: "password-field") do
        safe_join([
          form.password_field(method, **opts),
          tag.button(
            type: "button",
            class: "btn btn-ghost btn-sm password-toggle",
            data: { action: "password-visibility#toggle" },
            aria: { label: "Toggle password visibility" },
          ) do
            safe_join([
              tag.span(I18n.t("actions.show"), data: { password_visibility_target: "icon" }),
              tag.span(I18n.t("actions.hide"), data: { password_visibility_target: "icon" }, class: "hidden"),
            ])
          end,
        ])
      end
    end

    # @stimulus-components/read-more
    # Defaults through t(), not English literals: a default argument bypasses
    # the i18n discipline the rest of the tree keeps, and these render inside
    # a page whose default locale is nb.
    def read_more(text, lines: 3, more: nil, less: nil, class_name: "read-more-content")
      more ||= t("shared.read_more", default: "Read more")
      less ||= t("shared.read_less", default: "Read less")
      return "" if text.blank?

      tag.div(
        data: {
          controller: "read-more",
          read_more_more_text_value: more,
          read_more_less_text_value: less,
        },
      ) do
        safe_join([
          tag.div(simple_format(text, {}, sanitize: false), class: class_name, data: { read_more_target: "content" }),
          tag.button(type: "button", class: "btn-link", data: { action: "read-more#toggle" }) { more },
        ])
      end
    end
  end
end
