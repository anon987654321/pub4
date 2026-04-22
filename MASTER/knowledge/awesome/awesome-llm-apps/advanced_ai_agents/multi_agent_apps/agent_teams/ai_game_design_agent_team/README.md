ai_game_design_agent_team/
├─ README.md                # ← you are here
├─ requirements.txt         # Python dependencies for the optional demo UI
├─ run.sh                   # Starts the Master server and the UI
└─ src/
   ├─ agent_definitions.rb  # Ruby classes that implement each persona
   ├─ pipeline.rb           # Master pipeline configuration for this team
   ├─ tools/                # Custom tool implementations
   │   ├─ asset_generator.rb
   │   └─ level_balancer.rb
   └─ scripts/              # Evaluation & testing helpers
       ├─ evaluate.rb
       └─ test_playthrough.rb
