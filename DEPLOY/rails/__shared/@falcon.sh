cd "$BASE_DIR"

# -- CONFIGURE FALCON AS THE PRIMARY WEB SERVER --

bundle add falcon
bundle add async
bundle add async-redis
bundle add async-websocket

bundle install

# Generate Falcon configuration for each app
typeset -A apps_domains
apps_domains=(
  "brgen" "${BRGEN_PORT}"
  "bsdports" "${BSDPORTS_PORT}"
  "neuroticerotic" "${NEUROTICEROOT_PORT}"
)

for app in ${(k)apps_domains}; do
  port=${apps_domains[$app]}
  
  config_content=$(cat <<EOF
#!/usr/bin/env falcon-host
# Falcon for Rails with ActionCable support

ENV["RAILS_ENV"] ||= "production"

require_relative "./config/environment"
require "async/websocket/adapters/rack"

load :rack, :supervisor

Async do
  hostname = "localhost"

  rails = Rack::Builder.new do
    map "/cable" do
      run ActionCable.server
    end

    run Rails.application
  end

  rack hostname do
    endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:#{port}")
    app rails
  end

  supervisor
end
EOF
  )

  # Write the configuration to the file
  echo "$config_content" > "/home/${app}/${app}/config/falcon.rb"
done

