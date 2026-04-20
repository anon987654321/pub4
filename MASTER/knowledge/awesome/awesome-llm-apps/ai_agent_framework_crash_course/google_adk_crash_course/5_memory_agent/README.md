#Tutorial 5: Memory Agents - Sessions, State & Events

## What You’ll Learn
- Session management: maintain conversation context  
- State persistence: store and retrieve data  
- Event tracking: capture conversation flow  
- Memory types: in‑memory, database, cloud  
- Personalization: agents that recall preferences  

## Core Concepts

### Sessions
A session is a conversation container.  
Lifecycle: **Create → Active → Close**.  
Contains: user ID, events, memory state.

Example: Chatting with a travel agent creates a session that stores flight, hotel, and budget details.

### State
State holds current context.  
Typical fields:

- User preferences  
- Agent task  
- Tools used  
- Timestamp  

Example: A travel agent’s state may include destination, budget, dates.

### Events
Events are discrete interactions.  
Sequence:  1. User message  
2. Agent processing  
3. Agent response  

Each event records type, timestamp, and content.

### Session Runtime Flow
1. **Create session** with user ID and initialize state/memory.  2. **Loop**: receive input → process → update state → store event.  
3. **Close**: save final state and archive.

## Structure
1. **5_1_in_memory_conversation** – In‑memory session service  
2. **5_2_persistent_conversation** – Database‑backed session service  

## Prerequisites
- Python 3.11+  
- Google AI API key (obtain from AI Studio)  
- SQLite (bundled with Python)  
- Basic database knowledge (for level 2)

## How to Use
1. Read the concept section.  
2. Review the code in `agent.py`.  
3. Run the example (`streamlit run app.py`).  
4. Test multi‑turn conversations.  
5. Proceed to the next level.

## Features
- Clear explanations  - Minimal, functional code  
- Real‑world examples  
- Step‑by‑step instructions  
- Memory persistence demo  ## Next Steps
- Advanced agent patterns  - Custom memory services  
- Production deployment  

## Pro Tips
- Begin with in‑memory sessions.  
- Test with multi‑turn dialogues.  
- Inspect state via the ADK web UI.  
- Choose a memory strategy that fits the use case.