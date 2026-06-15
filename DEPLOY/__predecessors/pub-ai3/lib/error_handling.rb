# encoding: utf-8
# Error handling module to encapsulate common error handling logic

module ErrorHandling
  def with_error_handling
    yield
  rescue StandardError => e
    handle_error(e)
    nil # Return nil or an appropriate error response
  end

  def handle_error(exception)
    puts "An error occurred: #{exception.message}"
  end
end
