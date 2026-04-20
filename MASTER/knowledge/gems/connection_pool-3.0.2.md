$memcached = ConnectionPool.new(size: 5, timeout: 5) { Dalli::Client.new }
