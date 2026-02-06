# htmx_streaming.rb

# Rails + HTMX Streaming Patterns Implementation
# This file implements a controller for Server-Sent Events (SSE) in a Rails application.

# SSE Support for Progressive Responses
class StreamingController < ApplicationController

  # Method to initiate streaming response
  def stream_response
    # Set response headers for SSE
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Connection'] = 'keep-alive'

    # Example of sending a message every second
    5.times do |i|
      # Assuming each message contains a payload that can be JSON encoded
      message = { message: "Update number "+(i+1).to_s }
      # Send the message as SSE
      response.stream.write "data: #{message.to_json}\n\n"
      sleep 1  # Simulate processing delay
    end

    # Complete the stream
    response.stream.close
  end

  # Turbo Streams Integration example
  def turbo_stream_response
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append('messages', partial: 'messages/message', locals: { message: 'New message!' })
      end
    end
  end
end

# Chunked HTTP Response
# This utilizes the StreamingController to send chunked responses
class ChunkedResponseController < ApplicationController
  def chunked_response
    response.headers['Content-Type'] = 'text/plain'
    response.headers['Transfer-Encoding'] = 'chunked'

    5.times do |i|
      # Send each chunk
      response.stream.write("Chunk #{i + 1}\n")
      sleep 1  # Pause before sending next chunk
    end
    response.stream.close
  end
end

# Server-Sent Events formatting
# This is an example of how we format the data we send in SSE
module SSEFormatter
  def self.format(data)
    "data: #{data.to_json}\n\n"
  end
end
