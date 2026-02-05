class AdaptiveRetry
  def initialize(max_attempts: 5, wait_time: 1, context: {})
    @max_attempts = max_attempts
    @wait_time = wait_time
    @memory = []
    @context = context
  end

  def call
    attempts = 0
    begin
      yield
    rescue => e
      attempts += 1
      log_failure(e)

      if attempts < @max_attempts
        sleep(@wait_time)
        retry
      else
        raise "Max attempts reached. Last error: #{e.message}" 
      end
    end
  end

  private
  
  def log_failure(exception)
    @memory << { timestamp: Time.now.utc, error: exception.message, context: @context }
    # Here we can also integrate with critique system if needed
    # CritiqueIntegration.log(@memory.last) if CritiqueIntegration
  end
end
