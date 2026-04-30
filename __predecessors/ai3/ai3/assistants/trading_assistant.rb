# TradingAssistant – Handles market analysis and trading commands.
#
# Restored full logic from the old version.
class TradingAssistant
  def initialize
    @logger = Logger.new('logs/ai3.log', 'daily')
    @logger.level = Logger::INFO
  end

  def respond(input)
    @logger.info("TradingAssistant: Processing command: #{input}")
    handle_command(input)
  end

  def handle_command(command)
    if command =~ /^price (\w+)$/i
      fetch_price($1)
    else
      "Unknown trading command. Please use a command like 'price SYMBOL'."
    end
  end

  def fetch_price(symbol)
    @logger.info("Fetching price for #{symbol.upcase}")
    "Price of #{symbol.upcase}: $123.45"  # Simulated response
  end
end
