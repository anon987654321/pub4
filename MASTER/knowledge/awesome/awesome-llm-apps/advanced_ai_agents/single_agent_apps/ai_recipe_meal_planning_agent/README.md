# Clone the upstream repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/advanced_ai_agents/single_agent_apps/ai_recipe_meal_planning_agent

# Install Ruby dependencies
bundle install

# Run the agent
bundle exec ruby bin/plan_meal.rb \
  --diet vegan \
  --calories 2000 \
  --meals 3 \
  --days 5
