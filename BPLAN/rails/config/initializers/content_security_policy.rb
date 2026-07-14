# frozen_string_literal: true

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self, "https://fonts.gstatic.com"
    policy.style_src :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.script_src :self, :unsafe_inline
    policy.img_src :self, :data, "https:"
    policy.connect_src :self
    policy.frame_ancestors :none
    policy.base_uri :self
    policy.form_action :self, "mailto:"
  end
end