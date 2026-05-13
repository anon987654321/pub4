# hjerterom

## Food and reuse distribution network

hjerterom is a local food, reuse, and volunteer operations system built on Rails 8.

It should work more like a food bank than a social network.

The core job is simple: receive resources, sort them, pack them, distribute them, and keep the operation reliable.

## Value proposition

hjerterom helps local organizations run resource redistribution with less waste and better coordination.

It supports:

- food rescue
- weekly food boxes
- clothing reuse
- toy and book redistribution
- volunteer shifts
- donor pickup routes
- physical distribution points
- reuse and composting courses

## Core workflows

### Intake

Register donations from grocery stores, bakeries, restaurants, schools, churches, companies, and private donors.

Track:

- donor
- resource type
- quantity
- batch
- expiration
- storage need
- pickup time

### Inventory

Track resources after intake.

Core entities:

- food batch
- clothing lot
- toy lot
- book lot
- household goods lot
- storage location
- expiration date
- condition

### Packing

Support recurring box packing.

Track:

- box type
- household size
- dietary notes
- packed by
- packed at
- inventory used
- distribution status

### Distribution

Manage weekly pickup and delivery.

Track:

- pickup windows
- recipient queues
- delivery routes
- no-shows
- completed handoff
- remaining inventory

### Volunteers

Schedule and track operational work.

Roles:

- driver
- sorter
- packer
- front desk
- kitchen
- course host
- reuse shop helper

### Partners

Manage relationships with donors, landlords, municipalities, businesses, churches, and local organizations.

## Physical place

The physical location matters.

The software should support:

- distribution center operations
- cafe operations
- course schedules
- reuse shop inventory
- public visibility
- recurring visitors

The cafe is useful when it strengthens distribution, reuse, and local trust. It is not the main product.

## Systems to build next

### Route planning

Optimize pickup routes and delivery routes.

### Spoilage reduction

Warn when food is close to expiration.

### Demand forecasting

Estimate weekly need from historical distribution.

### Donor reporting

Show donors what was received, packed, and distributed.

### Recipient privacy

Protect recipient identity. Do not expose need, address, or household details without purpose.

### Reuse courses

Schedule courses in reuse, repair, composting, cooking, and household economy.

## Stack

Rails 8, PostgreSQL, Hotwire, Solid Queue, Active Storage, OpenBSD.

## Rails direction

Use Rails models and jobs for the operational core:

- `Donor`
- `DonationBatch`
- `InventoryItem`
- `DistributionBox`
- `Recipient`
- `PickupPoint`
- `Route`
- `VolunteerShift`
- `Partner`
- `Course`

Use Solid Queue for route jobs, notification jobs, reporting jobs, and recurring inventory checks.

Use Active Storage for receipts, donor documents, course material, and inventory photos.

Use Turbo for live packing screens and distribution status.

## Deploy

```zsh
cd ~/pub4/DEPLOY/rails/hjerterom
doas zsh hjerterom.sh
```

## Long-term goal

Build reliable software for local food banks, reuse centers, and resource redistribution hubs.