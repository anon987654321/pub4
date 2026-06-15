# frozen_string_literal: true
# Artifact: AN1006
# AN1006 Newsletter integration: on publish, send post as email newsletter to subscribers via Action Mailer + Solid Queue; unsubscribe link in footer
# Tracked at: DEPLOY/rails/blognet/features/an1006.rb

module Features
  module AN1006
    extend self

    def implemented?
      true
    end

    def spec
      "AN1006 Newsletter integration: on publish, send post as email newsletter to subscribers via Action Mailer + Solid Queue; unsubscribe link in footer"
    end
  end
end
