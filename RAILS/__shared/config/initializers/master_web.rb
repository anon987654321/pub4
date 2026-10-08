# frozen_string_literal: true

Rails.application.config.x.master_web_url = ENV.fetch("MASTER_WEB_URL", "https://ai.brgen.no")
