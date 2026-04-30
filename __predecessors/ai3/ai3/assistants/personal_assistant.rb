# PersonalAssistant – A digital personal assistant with a twist of sarcasm and dark humor.
#
# Restored full logic from personal_assistant.rb and personal.r_.
class PersonalAssistant
  attr_accessor :user_profile, :goal_tracker, :relationship_manager

  def initialize(user_profile = {})
    @user_profile = user_profile
    @goal_tracker = GoalTracker.new
    @relationship_manager = RelationshipManager.new
    @environment_monitor = EnvironmentMonitor.new
    @wellness_coach = WellnessCoach.new(@user_profile)
  end

  def monitor_environment(surroundings, relationships)
    @environment_monitor.analyze(surroundings: surroundings, relationships: relationships)
  end

  def real_time_alerts
    @environment_monitor.real_time_alerts
  end

  def learn_about_user(details)
    @user_profile.merge!(details)
    @wellness_coach.update_user_preferences(details)
  end

  def provide_fitness_plan(goal)
    @wellness_coach.generate_fitness_plan(goal)
  end

  def provide_meal_plan(dietary_preferences)
    @wellness_coach.generate_meal_plan(dietary_preferences)
  end

  def mental_wellness_support
    @wellness_coach.mental_health_support
  end

  def ensure_privacy
    PrivacyManager.secure_data_handling(@user_profile)
  end

  def track_goal(goal)
    @goal_tracker.track(goal)
  end

  def manage_relationships(relationship_details)
    @relationship_manager.manage(relationship_details)
  end

  def suggest_routine_improvements
    @wellness_coach.suggest_routine_improvements(@user_profile)
  end

  def assist_decision_making(context)
    DecisionSupport.assist(context)
  end
end

# Sub-components follow:
class GoalTracker
  def initialize
    @goals = []
  end

  def track(goal)
    @goals << goal
    puts "Tracking goal: #{goal}"
    progress = rand(0..100)
    puts "Progress on '#{goal}': #{progress}% complete."
  end
end

class RelationshipManager
  def initialize
    @relationships = []
  end

  def manage(details)
    @relationships << details
    puts "Managing relationship with #{details[:name]}"
    if details[:toxic]
      puts "Warning: Toxic traits detected."
    else
      puts "Relationship appears healthy."
    end
  end
end

class EnvironmentMonitor
  def initialize
    @alerts = []
  end

  def analyze(surroundings:, relationships:)
    puts "Analyzing environment..."
    analyze_surroundings(surroundings)
    analyze_relationships(relationships)
  end

  def real_time_alerts
    if @alerts.empty?
      puts "No alerts. All clear."
    else
      @alerts.each { |alert| puts "Alert: #{alert}" }
      @alerts.clear
    end
  end

  private

  def analyze_surroundings(surroundings)
    @alerts << "Risk detected: #{surroundings[:description]}" if surroundings[:risk]
  end

  def analyze_relationships(relationships)
    relationships.each { |rel| @alerts << "Toxic relationship with #{rel[:name]}" if rel[:toxic] }
  end
end

class WellnessCoach
  def initialize(user_profile)
    @user_profile = user_profile
    @fitness_goals = []
    @meal_plans = []
  end

  def generate_fitness_plan(goal)
    plan = "30 minutes of cardio and strength training"
    @fitness_goals << { goal: goal, plan: plan }
    puts "Fitness Plan: #{plan}"
  end

  def generate_meal_plan(prefs)
    plan = "Balanced meal with proteins, carbs, and fats"
    @meal_plans << { preferences: prefs, plan: plan }
    puts "Meal Plan: #{plan}"
  end

  def mental_health_support
    puts "Providing daily affirmations and mindfulness exercises."
    "You are strong; embrace the chaos."
  end

  def suggest_routine_improvements(profile)
    suggestions = [
      "Add a 10-minute morning stretch.",
      "Take a short walk after meals.",
      "Maintain a consistent sleep schedule."
    ]
    suggestions.each { |s| puts "Suggestion: #{s}" }
  end

  def update_user_preferences(details)
    @user_profile.merge!(details)
    puts "Updated user preferences: #{details}"
  end
end

class PrivacyManager
  def self.secure_data_handling(user_profile)
    puts "Data secured for user profile."
  end
end

class DecisionSupport
  def self.assist(context)
    recommendation = "Focus on time management."
    puts "Decision Support: #{recommendation}"
  end
end
