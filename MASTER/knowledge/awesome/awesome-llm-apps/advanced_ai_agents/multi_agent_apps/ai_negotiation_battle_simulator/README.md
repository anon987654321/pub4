+-------------------+   +-------------------+   +-------------------+
|   BattleArena     |   |   VS Display      |   |   ChatSide (AG‑UI)|
|   Timeline        |   |   (BUY / SELL)    |   |   (AG‑UI)         |
+--------+----------+   +--------+----------+   +--------+----------+
         |                       |                       |
         |   AG‑UI events        |                       |
         +-----------------------+-----------------------+
                                 |
                             +---v---+
                             | CopilotKit |
                             | Runtime    |
                             +---+---+
                                 | HTTP / SSE
                             +---v---+
                             | FastAPI |
                             | ADK Agent|
                             +---+---+
                                 | Tools
        +------------------------+------------------------+
        | configure_negotiation  start_negotiation        |
        | buyer_make_offer       seller_respond           |
        +---------------------------------------------------+
