# bsdports

## Official OpenBSD ports index

bsdports is a semantic interface and public index for the OpenBSD ports ecosystem.

The goal is to become the canonical searchable interface for OpenBSD ports, packages, dependencies, documentation, and infrastructure knowledge.

It combines:

- package indexing
- semantic search
- dependency visualization
- security intelligence
- infrastructure recommendations
- AI-assisted exploration

into one OpenBSD knowledge system.

## Value proposition

The OpenBSD ports tree contains decades of infrastructure knowledge.

bsdports should make that knowledge:

- searchable
- understandable
- explorable
- visual
- semantically connected
- beginner friendly

while remaining useful to experienced operators.

## How it works

bsdports seeds itself from official OpenBSD mirrors.

It downloads `ports.tar.gz`, extracts the tree, walks Makefiles, and imports:

- package metadata
- descriptions
- URLs
- dependencies
- categories
- platforms
- maintainers

into PostgreSQL.

## Core concepts

### Semantic infrastructure search

Search for:

- secure mail servers
- Rails hosting stacks
- minimal VPS systems
- reverse proxies
- VPN systems
- OpenBSD desktop software

instead of exact package names.

### Infrastructure graph

Visualize:

- dependencies
- trust chains
- maintenance activity
- package relationships
- stack pairings
- security exposure

### Security intelligence

Overlay:

- CVEs
- outdated packages
- stale dependencies
- upstream activity
- maintenance gaps

### Learning system

Teach:

- OpenBSD basics
- ports
- PF
- relayd
- pledge and unveil
- package maintenance
- secure deployment

## Models

| Model | Purpose |
|---|---|
| `Platform` | OpenBSD release branch |
| `Category` | Top-level ports category |
| `Port` | Individual package metadata |

## Features

- semantic search
- dependency exploration
- category browsing
- platform filtering
- package recommendations
- stack recommendations
- infrastructure tutorials
- AI-assisted exploration

## Systems to build next

### Architecture generators

Generate:

- deployment plans
- hardened VPS stacks
- package recommendations
- service layouts
- infrastructure diagrams

### Semantic command search

Examples:

- how to secure ssh
- how to host Rails on OpenBSD
- how to configure relayd

### Relationship systems

Show:

- alternatives
- complementary packages
- common combinations
- maintainer ecosystems

## Stack

Rails 8, PostgreSQL, pgvector, Falcon, Hotwire, OpenBSD.

## AI direction

Use embeddings, semantic retrieval, GraphRAG, and infrastructure knowledge graphs.

## Deploy

```zsh
doas zsh DEPLOY/rails/bsdports/bsdports.sh
```

## Long-term goal

Become the official searchable knowledge and discovery layer for the OpenBSD ports ecosystem.