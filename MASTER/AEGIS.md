# Aegis

Aegis is the proactive-bodyguard concept: passive sensing, active analysis,
preemptive action. Written for a city it is a hard build and a poor business.
Written for the water it is a narrower build with paying customers, and it is
the case where this runtime's offline-first design stops being a preference and
becomes the product.

**The urban threat model does not port.** It assumes an adversary who is human,
intentional, and three seconds away, in a place with dense infrastructure. At
sea the threat is environmental and indifferent, the timescale is twenty minutes
to twelve hours, rescue latency is hours rather than minutes, and connectivity
is absent by default rather than merely degraded. Every intervention that
depends on deceiving a person — the synthetic phone call, the fake system
update, the lit-street route — has no one to deceive and nowhere to walk. Gait
analysis, proximity tailing and weapon identification go with them.

What survives is small and gets much stronger. Immersion and sudden-deceleration
detection replace the acoustic and gait tiers. The last-known-position heartbeat,
a footnote in the urban spec because the city has signal, becomes the entire
value proposition. The forensic packet already has a regulatory home, because
voyage data recording is mandated on commercial vessels and is currently dumb.

**Man overboard is the anchor, and the only one worth starting from.** It maps
onto the existing pipeline almost unchanged: immersion plus acceleration anomaly
triggers, biometrics confirm the wearer is alive, an AIS-MOB and satellite burst
carries position, and the packet is the record. It is far more tractable than
the urban case because there is no intent to model and no adversary adapting to
the detector, and it drops the whole privacy surface with them. Existing MOB
beacons are pull-cord or water-contact triggers with no discrimination and no
prediction. The gap a model actually fills is drift: cold-water displacement is
predictable from sea state and current, and a search wants the probable position
twenty minutes from now, not the position at the moment of the fall.

**The gate is hardware, not software.** A phone cannot host this — salt,
immersion, battery, and the fact that it rides in a pocket rather than against
skin. The sensing substrate has to become a wearable or a vessel-mounted box
before any of the sensing tiers are worth writing. So the order is: prove the
tier-one anomaly stack on phones on land, where iteration is cheap, then port
detection to marine hardware, where the regulation and the budgets are. The
urban build is the laboratory, not the product.

**Do not scaffold the sensing tiers yet.** Stub sensors, placeholder threat
classes and a maritime module wired to nothing would be this tree's dominant
defect committed deliberately, and `data/soul.yml` forbids it under
anti_simulation. Nothing in this program is written until it has a reader.

The one piece buildable today with no hardware and no speculation is the drift
model: a pure function from entry position, sea state, current and elapsed time
to a probable-position ellipse, testable against published search-and-rescue
drift data. It is useful on its own to anyone running a search, it is the part
with real intellectual content, and it is falsifiable — which the rest is not
until there is a device. Start there or start nowhere.

Norway is the place to do it: the fishing fleet, the aquaculture pens, the
offshore wind buildout, Sjøfartsdirektoratet, and an Innovasjon Norge case that
argues far more readily for maritime safety than for a constitutional runtime.
It is the same pitch as `MASTER/README.md` makes, with a body attached.

---
