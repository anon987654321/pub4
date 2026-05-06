# frozen_string_literal: true

load :rack, :supervisor

hostname = File.basename(__dir__)
port = ENV.fetch("PORT", 11006).to_i

rack hostname do
  endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:#{port}").with(protocol: Async::HTTP::Protocol::HTTP2)
end
