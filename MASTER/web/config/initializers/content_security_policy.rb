# frozen_string_literal: true

# Restart server after editing.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self, :data, "https://fonts.gstatic.com"
    policy.img_src :self, :data, "https://i.ytimg.com"
    policy.object_src :none
    policy.script_src :self, "https://www.youtube.com", "https://s.ytimg.com"
    policy.style_src :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.connect_src :self, "https://www.youtube.com", "https://youtu.be"
    policy.media_src :self, :blob
    policy.frame_src "https://www.youtube.com", "https://www.youtube-nocookie.com"
  end
end
