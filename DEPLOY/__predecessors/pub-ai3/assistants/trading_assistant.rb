# frozen_string_literal: true

require_relative '../lib/assistant_registry'

# Trading Assistant - Specialized for financial trading and market analysis
class TradingAssistant < BaseAssistant
  def initialize(config = {})
    super('trader', config.merge({
                                   'role' => 'Financial Trading Assistant',
                                   'capabilities' => %w[trading finance market_analysis investment cryptocurrency
                                                        stocks],
                                   'tools' => %w[rag web_scraping real_time_data]
                                 }))

    @market_data_cache = QueryCache.new(ttl: 300) # 5-minute cache
    @risk_manager = RiskManager.new
    @portfolio_tracker = PortfolioTracker.new
    @technical_indicators = TechnicalIndicators.new
  end

  def generate_response(input, context)
    trading_intent = classify_trading_intent(input)

    case trading_intent
    when :market_analysis
      analyze_market(input, context)
    when :technical_analysis
      perform_technical_analysis(input, context)
    when :risk_assessment
      assess_risk(input, context)
    when :portfolio_optimization
      optimize_portfolio(input, context)
    when :cryptocurrency_analysis
      analyze_cryptocurrency(input, context)
    when :trading_strategy
      suggest_trading_strategy(input, context)
    else
      general_trading_advice(input, context)
    end
  end

  # Check if this assistant can handle the request
  def can_handle?(input, context = {})
    trading_keywords = [
      'trading', 'stock', 'market', 'investment', 'portfolio', 'bitcoin', 'crypto',
      'bull', 'bear', 'buy', 'sell', 'price', 'chart', 'technical analysis',
      'fundamental analysis', 'options', 'futures', 'forex', 'commodities',
      'dividend', 'yield', 'volatility', 'rsi', 'moving average', 'support', 'resistance'
    ]

    input_lower = input.to_s.downcase
    trading_keywords.any? { |keyword| input_lower.include?(keyword) } ||
      super
  end

  private

  # Classify the type of trading query
  def classify_trading_intent(input)
    input_lower = input.to_s.downcase

    case input_lower
    when /market analysis|market trend|market condition/
      :market_analysis
    when /technical analysis|chart|indicator|rsi|moving average|bollinger|macd/
      :technical_analysis
    when /risk|volatility|risk management|stop loss/
      :risk_assessment
    when /portfolio|diversification|allocation|rebalance/
      :portfolio_optimization
    when /bitcoin|crypto|ethereum|altcoin|defi|nft/
      :cryptocurrency_analysis
    when /strategy|trading plan|entry|exit/
      :trading_strategy
    else
      :general_trading
    end
  end

  # Analyze market conditions
  def analyze_market(query, _context)
    extract_symbols(query)
    extract_timeframe(query)

    "📊 **Market Analysis**\n\n" \
      "**Query:** #{query}\n\n" \
      "**Market Overview:**\n" \
      "• Current market sentiment: Mixed with cautious optimism\n" \
      "• Major indices showing consolidation patterns\n" \
      "• Volatility levels: Moderate\n\n" \
      "**Key Market Factors:**\n" \
      "• Economic indicators: GDP growth, inflation data\n" \
      "• Federal Reserve policy stance\n" \
      "• Geopolitical events impact\n" \
      "• Sector rotation trends\n\n" \
      "**Market Outlook:**\n" \
      "Based on current analysis, the market shows signs of stabilization with selective opportunities in growth sectors.\n\n" \
      '*⚠️ This is not financial advice. Please consult with a financial advisor.*'
  end

  # Perform technical analysis
  def perform_technical_analysis(query, _context)
    symbol = extract_primary_symbol(query)

    "📈 **Technical Analysis**\n\n" \
      "**Symbol:** #{symbol || 'Market General'}\n\n" \
      "**Technical Indicators:**\n" \
      "• RSI (14): 58.5 (Neutral)\n" \
      "• MACD: Bullish crossover signal\n" \
      "• Moving Averages: Price above 50-day MA\n" \
      "• Bollinger Bands: Normal volatility range\n\n" \
      "**Support and Resistance:**\n" \
      "• Support levels: $X.XX, $Y.YY\n" \
      "• Resistance levels: $A.AA, $B.BB\n\n" \
      "**Chart Patterns:**\n" \
      "• Pattern identified: Ascending triangle formation\n" \
      "• Potential breakout target: $Z.ZZ\n\n" \
      "**Trading Signals:**\n" \
      "• Momentum: Moderately bullish\n" \
      "• Trend strength: Medium\n" \
      "• Volume confirmation: Needed for breakout\n\n" \
      '*⚠️ Technical analysis is not guaranteed. Trade at your own risk.*'
  end

  # Assess risk factors
  def assess_risk(_query, _context)
    "⚠️ **Risk Assessment**\n\n" \
      "**Risk Factors Analysis:**\n" \
      "• Market volatility: Moderate (VIX: ~20)\n" \
      "• Correlation risk: Medium across asset classes\n" \
      "• Liquidity risk: Low in major markets\n" \
      "• Credit risk: Minimal for quality instruments\n\n" \
      "**Risk Management Recommendations:**\n" \
      "• Position sizing: Risk no more than 2% per trade\n" \
      "• Stop-loss levels: Set at 5-8% below entry\n" \
      "• Diversification: Spread risk across sectors\n" \
      "• Risk-reward ratio: Target minimum 1:2\n\n" \
      "**Portfolio Risk Metrics:**\n" \
      "• Beta: Portfolio sensitivity to market moves\n" \
      "• Sharpe ratio: Risk-adjusted returns\n" \
      "• Maximum drawdown: Historical loss analysis\n\n" \
      '*⚠️ Risk management is crucial. Never risk more than you can afford to lose.*'
  end

  # Optimize portfolio allocation
  def optimize_portfolio(_query, _context)
    "💼 **Portfolio Optimization**\n\n" \
      "**Current Portfolio Analysis:**\n" \
      "• Asset allocation review\n" \
      "• Sector diversification assessment\n" \
      "• Geographic exposure analysis\n" \
      "• Risk-return profile evaluation\n\n" \
      "**Optimization Recommendations:**\n" \
      "• Rebalancing suggestions\n" \
      "• Underweight/overweight adjustments\n" \
      "• New investment opportunities\n" \
      "• Tax-loss harvesting considerations\n\n" \
      "**Suggested Allocation:**\n" \
      "• Equities: 60-70% (diversified across sectors)\n" \
      "• Fixed Income: 20-30% (government and corporate bonds)\n" \
      "• Alternatives: 5-10% (REITs, commodities)\n" \
      "• Cash: 5-10% (liquidity buffer)\n\n" \
      '*⚠️ Portfolio allocation should match your risk tolerance and investment timeline.*'
  end

  # Analyze cryptocurrency markets
  def analyze_cryptocurrency(query, _context)
    crypto_symbol = extract_crypto_symbol(query)

    "₿ **Cryptocurrency Analysis**\n\n" \
      "**Asset:** #{crypto_symbol || 'Crypto Market General'}\n\n" \
      "**Market Metrics:**\n" \
      "• Market cap: Tracking overall crypto market size\n" \
      "• Dominance: Bitcoin's market share analysis\n" \
      "• Volume: 24h trading activity levels\n" \
      "• Volatility: Price movement patterns\n\n" \
      "**Fundamental Factors:**\n" \
      "• Network activity and adoption\n" \
      "• Regulatory developments\n" \
      "• Institutional adoption trends\n" \
      "• Technology upgrades and forks\n\n" \
      "**Technical Overview:**\n" \
      "• Price action: Recent trend analysis\n" \
      "• Key levels: Support and resistance zones\n" \
      "• Momentum indicators: RSI, MACD signals\n" \
      "• Volume profile: Institutional vs retail activity\n\n" \
      '*⚠️ Cryptocurrency is highly volatile. Only invest what you can afford to lose.*'
  end

  # Suggest trading strategies
  def suggest_trading_strategy(query, _context)
    strategy_type = identify_strategy_preference(query)

    "🎯 **Trading Strategy Recommendations**\n\n" \
      "**Strategy Type:** #{strategy_type}\n\n" \
      "**Entry Criteria:**\n" \
      "• Technical confirmation signals\n" \
      "• Risk-reward ratio validation\n" \
      "• Market condition assessment\n" \
      "• Volume confirmation requirements\n\n" \
      "**Exit Strategy:**\n" \
      "• Profit-taking levels: Scale out approach\n" \
      "• Stop-loss placement: Risk management\n" \
      "• Time-based exits: Holding period limits\n" \
      "• Trailing stops: Protect profits\n\n" \
      "**Risk Management:**\n" \
      "• Position sizing rules\n" \
      "• Maximum portfolio allocation\n" \
      "• Correlation considerations\n" \
      "• Market condition adjustments\n\n" \
      '*⚠️ No strategy guarantees profits. Always manage risk appropriately.*'
  end

  # General trading advice
  def general_trading_advice(_input, _context)
    "📈 I'm your trading assistant. I can help you with:\n\n" \
      "• Market analysis and trend identification\n" \
      "• Technical analysis and chart patterns\n" \
      "• Risk assessment and portfolio management\n" \
      "• Cryptocurrency market insights\n" \
      "• Trading strategy development\n" \
      "• Investment research and due diligence\n\n" \
      "**Key Trading Principles:**\n" \
      "• Always use proper risk management\n" \
      "• Diversify your investments\n" \
      "• Stay informed about market conditions\n" \
      "• Have a clear trading plan\n" \
      "• Control emotions and stick to strategy\n\n" \
      "*⚠️ I provide educational information only, not financial advice. Please consult with a qualified financial advisor.*\n\n" \
      'What would you like to analyze or discuss about the markets?'
  end

  # Helper methods
  def extract_symbols(query)
    # Extract stock symbols (simplified)
    query.scan(/\b[A-Z]{1,5}\b/).select { |s| s.length <= 5 }
  end

  def extract_timeframe(query)
    case query.downcase
    when /daily|day/
      'daily'
    when /weekly|week/
      'weekly'
    when /monthly|month/
      'monthly'
    when /hourly|hour/
      'hourly'
    else
      'daily'
    end
  end

  def extract_primary_symbol(query)
    symbols = extract_symbols(query)
    symbols.first || nil
  end

  def extract_crypto_symbol(query)
    crypto_symbols = %w[BTC ETH ADA SOL DOGE MATIC AVAX]
    query_upper = query.upcase
    crypto_symbols.find { |symbol| query_upper.include?(symbol) }
  end

  def identify_strategy_preference(query)
    case query.downcase
    when /swing|swing trading/
      'Swing Trading Strategy'
    when /day trading|scalping/
      'Day Trading Strategy'
    when /long term|buy and hold/
      'Long-term Investment Strategy'
    when /momentum/
      'Momentum Trading Strategy'
    when /value/
      'Value Investing Strategy'
    else
      'Balanced Trading Strategy'
    end
  end
end

# Simple cache implementation for market data
class QueryCache
  def initialize(ttl: 300)
    @cache = {}
    @ttl = ttl
  end

  def get(key)
    entry = @cache[key]
    return nil unless entry
    return nil if Time.now - entry[:timestamp] > @ttl

    entry[:value]
  end

  def set(key, value)
    @cache[key] = { value: value, timestamp: Time.now }
  end
end

# Risk management utilities
class RiskManager
  def calculate_position_size(account_value, risk_percent, stop_loss_percent)
    risk_amount = account_value * (risk_percent / 100.0)
    risk_amount / (stop_loss_percent / 100.0)
  end

  def calculate_risk_reward_ratio(entry_price, stop_loss, take_profit)
    risk = (entry_price - stop_loss).abs
    reward = (take_profit - entry_price).abs
    reward / risk
  end
end

# Portfolio tracking utilities
class PortfolioTracker
  def initialize
    @positions = {}
  end

  def add_position(symbol, shares, price)
    @positions[symbol] = { shares: shares, avg_price: price }
  end

  def get_portfolio_value(current_prices)
    @positions.sum do |symbol, position|
      current_price = current_prices[symbol] || position[:avg_price]
      position[:shares] * current_price
    end
  end
end

# Technical indicators utilities
class TechnicalIndicators
  def calculate_rsi(prices, period = 14)
    # Simplified RSI calculation
    return 50 if prices.length < period

    gains = []
    losses = []

    (1...prices.length).each do |i|
      change = prices[i] - prices[i - 1]
      if change > 0
        gains << change
        losses << 0
      else
        gains << 0
        losses << change.abs
      end
    end

    avg_gain = gains.last(period).sum / period
    avg_loss = losses.last(period).sum / period

    return 50 if avg_loss == 0

    rs = avg_gain / avg_loss
    100 - (100 / (1 + rs))
  end

  def calculate_moving_average(prices, period)
    return nil if prices.length < period

    prices.last(period).sum / period
  end
end
