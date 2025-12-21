#!/usr/bin/env zsh
# Fix Falcon configuration for all Rails apps

cd ~/pub4/rails || exit 1

for app in brgen amber hjerterom baibl blognet dating marketplace brgen_playlist; do
  [[ -d "$app" ]] || continue
  
  print "Fixing Falcon config for $app..."
  cd "$app" || continue
  
  # Generate correct Falcon config
  cat > config/falcon.rb << 'FALCON_EOF'
#!/usr/bin/env -S falcon-host
# frozen_string_literal: true

require "falcon/environment/rack"

hostname = File.basename(__dir__)

service hostname do
  include Falcon::Environment::Rack
  
  # Preload Rails environment before forking
  preload "preload.rb"
  
  # Worker processes
  count ENV.fetch("WEB_CONCURRENCY", 2).to_i
  
  # Port configuration
  port_value = ENV.fetch("PORT", 3000).to_i
  
  # HTTP/1.1 endpoint
  endpoint do
    Async::HTTP::Endpoint.parse("http://0.0.0.0:#{port_value}")
      .with(protocol: Async::HTTP::Protocol::HTTP11)
  end
end
FALCON_EOF

  # Create preload.rb for Rails environment
  cat > preload.rb << 'PRELOAD_EOF'
# frozen_string_literal: true
require_relative "config/environment"
PRELOAD_EOF

  chmod +x config/falcon.rb
  cd ..
done

print "✓ All Falcon configs fixed"
