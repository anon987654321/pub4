# Restart server after editing.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self, :data, "https://fonts.gstatic.com"
    policy.img_src :self, :data
    policy.object_src :none
    policy.script_src :self
    policy.style_src :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.connect_src :self
    policy.media_src :self, :blob
  end
end
