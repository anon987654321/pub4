# frozen_string_literal: true

# Tool for web research.
# Uses the built‑in Runner to perform paginated searches with rate‑limit handling
# and LLM‑driven result synthesis.
# Parameters:
#   query:        String – the search phrase.
#   max_results:  Integer – maximum results to retrieve (default: 5).
#   max_turns:    Integer – LLM interaction depth (default: 3).
#   temperature:  Float – LLM creativity (default: 0.2).
@function_tool(
  name: "research",
  description: "Search the web for information relevant to the user's query."
)
def research(query:, max_results: 5, max_turns: 3, temperature: 0.2)
  # Validate basic types to avoid runtime errors.
  raise ArgumentError, "query must be a String" unless query.is_a?(String)
  raise ArgumentError, "max_results must be an Integer" unless max_results.is_a?(Integer)
  raise ArgumentError, "max_turns must be an Integer" unless max_turns.is_a?(Integer)
  raise ArgumentError, "temperature must be a Numeric" unless temperature.is_a?(Numeric)

  # Delegate the heavy lifting to the built‑in Runner.
  # Runner handles pagination, rate‑limits and LLM interaction.
  Runner.run(
    query:        query,
    max_results:  max_results,
    max_turns:    max_turns,
    temperature: temperature
  )
end