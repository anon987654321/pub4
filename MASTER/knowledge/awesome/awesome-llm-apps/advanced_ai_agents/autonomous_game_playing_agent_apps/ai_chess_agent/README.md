ai_chess_game/
├─ agent.rb            # Master::Agent subclass – wires the pipeline together
├─ board.rb            # Immutable board representation, FEN parser, move legality
├─ move_generator.rb   # Builds LLM prompts, parses the model’s move suggestions
├─ evaluator.rb        # Scores positions, hooks into Master::Quality for feedback
└─ run.rb              # Simple CLI entry point
