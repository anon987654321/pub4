module MASTER
  class Router
    MAX_RETRIES = 2

    def call(prompt)
      tries = 0
      begin
        tries += 1
        return primary.call(prompt)
      rescue BudgetError
        warn_once("openrouter credit exhausted, switching model")
        return fallback.call(prompt)
      rescue => e
        retry if tries < MAX_RETRIES
        raise e
      end
    end

    def warn_once(msg)
      return if @warned
      puts "router: #{msg}"
      @warned = true
    end
  end
end
