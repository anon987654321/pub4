# Initialise a pool with 5 connections, 5‑second checkout timeout
memcached = ConnectionPool.new(size: 5, timeout: 5) { Dalli::Client.new }

# Use a connection
memcached.with do |client|
  client.set('key', 'value')
  client.get('key') # => "value"
end
