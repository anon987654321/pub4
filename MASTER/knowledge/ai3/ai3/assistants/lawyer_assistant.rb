# LawyerAssistant – Provides legal consultation with psychological insights.
#
# Restored full logic from the old version.
class LawyerAssistant
  def initialize(target = 'default_case', case_data = { communication_history: [] })
    @target = target
    @case_data = case_data
    @logger = Logger.new('logs/ai3.log', 'daily')
    @logger.level = Logger::INFO
    @intervention_queue = []
    @negotiation_strategies = []
    @emotional_state = analyze_emotional_state
  end

  def analyze_emotional_state
    @case_data[:communication_history].map { |comm| emotional_analysis(comm) }.compact
  end

  def emotional_analysis(comm)
    case comm[:text]
    when /stress|anxiety|overwhelmed/
      { comm_id: comm[:id], emotion: :anxiety }
    when /happy|excited|joy/
      { comm_id: comm[:id], emotion: :joy }
    when /anger|frustration|rage/
      { comm_id: comm[:id], emotion: :anger }
    when /fear|worried|scared/
      { comm_id: comm[:id], emotion: :fear }
    else
      nil
    end
  end

  def respond(input)
    @logger.info("LawyerAssistant: Received input: #{input}")
    start_consultation(input)
  end

  def start_consultation(issue)
    if issue.nil? || issue.strip.empty?
      "Please describe your legal issue in detail."
    else
      "Analyzing legal issue: #{issue}. Consultation initiated."
    end
  end
end
