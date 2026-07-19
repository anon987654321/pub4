#!/usr/bin/env -S falcon-host
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true

load :rack

count Integer(ENV.fetch("FALCON_COUNT", 2))

rack "master" do
  mount Rack::Builder.parse_file("config.ru")
end
