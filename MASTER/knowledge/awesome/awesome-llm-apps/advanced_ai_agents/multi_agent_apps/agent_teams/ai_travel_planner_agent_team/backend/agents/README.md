# TripCraft AI – Agent Architecture

TripCraft AI orchestrates a team of specialized agents (via **Agno**) to generate fully personalized travel plans.

## Agent Roster

| Agent | Responsibility |
|-------|-----------------|
| **Destination Explorer** | Research attractions (hours, fees, visit length, accessibility). |
| **Hotel Search** | Find lodging that matches location, budget, amenities, and room type; return price, cancellation policy, and proximity. |
| **Dining** | Recommend restaurants with cuisine, price, dietary options, ambience, and distance from the hotel or activities. |
| **Budget** | Break down total cost, allocate funds, suggest savings, handle currency conversion, and reserve an emergency buffer. |
| **Flight Search** | Produce itineraries with routes, airlines, schedules, layovers, and airport‑to‑hotel transfers. |
| **Itinerary Specialist** | Stitch an hour‑by‑hour schedule, optimise travel time, add buffers for traffic/weather, and adapt to user feedback. |

## Coordination Flow

1. **Preference Ingestion** – Parse user criteria (dates, interests, budget, constraints).  
2. **Task Delegation** – Coordination layer assigns subtasks to the appropriate agents.  
3. **Parallel Execution** – Agents run concurrently, each returning a structured payload.  
4. **Merge & Resolve** – Consolidate outputs, dedupe overlaps, and reconcile timeline conflicts.  
5. **Logistics Sync** – Budget and Flight agents validate financial and feasibility limits.  
6. **Final Synthesis** – Itinerary Specialist emits a cohesive schedule with contingencies.

## Tooling

| Tool | Role |
|------|------|
| **ReasoningTools** | Optimisation, logical inference, and cross‑agent decision making. |
| **ExaTools** | Deep web research for up‑to‑date attraction data, reviews, and pricing. |
| **FirecrawlTools** | Real‑time scraping of dynamic sources (event calendars, live flight feeds). |

## Deliverables

- **Executive Summary** – High‑level trip concept.  
- **Travel Logistics** – Flights, transfers, and ground transport.  
- **Day‑by‑Day Itinerary** – Hourly schedule with activities, meals, and downtime.  
- **Accommodation Details** – Hotel info, check‑in/out times, amenities.  
- **Curated Activities** – Descriptions, links, and reservation requirements.  
- **Budget Breakdown** – Itemised costs, currency conversion, and contingency reserves.  

## Design Principles

1. **User‑Centric** – Translate preferences into concrete travel goals.  
2. **Comprehensive Research** – Aggregate multiple data sources for freshness and accuracy.  
3. **Practical Recommendations** – Prioritise feasible, high‑value options.  
4. **Contingency Planning** – Include backups and flexible bookings.  
5. **Clear Communication** – Produce readable, well‑structured outputs.  
6. **Budget Discipline** – Keep every recommendation within the financial envelope.  

## Integration

Expose a single **Agent API** endpoint that accepts user preferences and returns the assembled travel package as JSON:

```http
POST /api/v1/agents/plan
Content-Type: application/json

{
  "preferences": {
    "dates": ["2025-06-01", "2025-06-07"],
    "budget": 2500,
    "interests": ["culture", "food", "outdoors"],
    "constraints": { "max_flight_time": 5 }
  }
}
```

The backend renders this JSON in the web UI and persists it for future revisions.