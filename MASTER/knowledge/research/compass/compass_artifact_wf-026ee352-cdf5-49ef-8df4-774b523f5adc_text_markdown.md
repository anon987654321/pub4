# No-Moving-Parts Propulsion for Saucer-Shaped Spacecraft: 15 Concepts Ranked by Feasibility

The most realistic propulsion systems for a monolithic saucer craft combine **proven electric propulsion** (Hall/ion thrusters at TRL 9) with **emerging MHD and plasma technologies** (TRL 3-5) optimized for disc geometry. Exotic concepts like warp drives and quantum vacuum thrusters fail physics validation—the EmDrive and Mach effect thrusters were definitively debunked by Dresden University in 2021, leaving no credible reactionless propulsion candidates. The saucer configuration uniquely benefits circumferential electrode arrays for **360-degree thrust vectoring** and uniform plasma sheath management, making magnetohydrodynamic atmospheric flight the most geometry-optimized approach, while established electric propulsion provides the highest near-term readiness.

---

## The top five near-term candidates for implementation

Three propulsion systems emerge as immediately buildable with current technology: **Hall thruster arrays** (TRL 9, flight-proven on 6,000+ Starlink satellites), **gridded ion engine clusters** (TRL 9, demonstrated on Dawn and DART missions), and **pulsed plasma thrusters** (TRL 7-9, operational since 1964). Two mid-term systems offer higher performance with modest development: **high-power MPD thrusters** with superconducting magnets (TRL 4-5, recently achieved **76.6% efficiency** at 150 kW) and **atmospheric MHD drives** exploiting disc geometry's natural field symmetry. The saucer shape provides a structural advantage for these systems—electromagnetic reaction forces distribute uniformly across the circular hull rather than concentrating at discrete mounting points.

| Rank | Concept | TRL | Realism Score | Power | Thrust | Timeline |
|------|---------|-----|---------------|-------|--------|----------|
| 1 | Hall Thruster Array | 9 | 10/10 | 0.5-100 kW | mN-5.4 N | Now |
| 2 | Gridded Ion Cluster | 9 | 10/10 | 0.6-7.4 kW | 25-235 mN | Now |
| 3 | Pulsed Plasma (PPT) | 7-9 | 9/10 | 1-150 W | μN-mN | Now |
| 4 | MPD Superconducting | 4-5 | 8/10 | 100 kW-30 MW | 2.5-200 N | 5-10 yr |
| 5 | Atmospheric MHD | 3-4 | 7/10 | 1-30 MW | kN-class | 10-15 yr |

---

## Concept 1: Circumferential Hall Thruster Array

**Physics principle**: Crossed electric and magnetic fields trap electrons in a Hall current loop while electrostatically accelerating ions. The quasi-neutral plasma exhaust provides thrust without grid erosion issues. This is the most mature electric propulsion technology with **50-76% efficiency** demonstrated.

**Configuration for saucer craft**: Eight to twelve annular Hall thrusters arranged around the disc perimeter, each independently gimbaled electrically (no mechanical gimbal—magnetic field steering). The X3 nested Hall thruster at University of Michigan demonstrates **5.4 N thrust at 100 kW** from a single 80-cm diameter unit, validating high-power scaling.

**Technical specifications**:
- Specific impulse: **1,500-3,000 seconds** (adjustable)
- Thrust-to-power: **60-100 mN/kW**
- Propellant: Xenon (preferred), krypton, or argon
- Electrode life: **>50,000 hours** demonstrated
- Mass utilization efficiency: **90-99%**

**Key challenges**: Propellant storage mass for extended missions; clustering interactions (plume cross-talk); power processing unit mass at high power. Starlink's krypton Hall thrusters demonstrate cost reduction through alternative propellants.

**Materials required**: Boron nitride discharge channel; samarium-cobalt or neodymium magnets; molybdenum or carbon-carbon anodes; tungsten cathodes.

**Realism score**: **10/10**—Flight-proven on thousands of operational spacecraft. The NASA AEPS program is developing **12.5 kW Hall thrusters** for Lunar Gateway with planned 2025+ deployment.

---

## Concept 2: High-Isp Gridded Ion Cluster

**Physics principle**: Electron bombardment ionizes xenon propellant; charged grids at **1,000-1,800 V** accelerate ions to exhaust velocities of 30-40 km/s. The NEXT-C thruster achieves **70% total efficiency** with **4,220 seconds specific impulse**.

**Configuration for saucer craft**: Central ion engine cluster (4-8 thrusters) with collective thrust vectoring via differential throttling. Disc geometry allows symmetric propellant distribution and omnidirectional solar array integration.

**Technical specifications**:
- NASA NEXT performance: **0.6-7.4 kW power range**
- Thrust: **25-235 mN** per thruster
- Total impulse: **17-18 million N·s** per thruster
- Thruster mass: **<14 kg**; PPU mass: **<36 kg**
- Grid life: **>50,000 hours** with carbon-carbon grids

**Key challenges**: Grid erosion from ion impingement; xenon cost (~$850/kg); PPU complexity; low thrust density requires long mission durations.

**Materials required**: Molybdenum or carbon-carbon grids; pyrolytic graphite discharge chamber; CFRP structural components.

**Realism score**: **10/10**—DART mission demonstrated 1,000+ hours operation in 2021-2022. Dawn spacecraft achieved **11.5 km/s total ΔV** using NSTAR ion engines.

---

## Concept 3: Solid-State Pulsed Plasma Thrusters

**Physics principle**: Capacitor discharge ablates solid PTFE (Teflon) propellant, creating plasma accelerated by Lorentz force (j×B) in a quasi-railgun configuration. Completely solid-state with propellant embedded in structure.

**Configuration for saucer craft**: Distributed PPT modules embedded around hull perimeter for attitude control and secondary propulsion. Teflon fuel bars integrated into structural panels.

**Technical specifications**:
- Power: **1-150 W average**
- Impulse bit: **10-100 μN·s per pulse**
- Specific impulse: **1,000-1,400 s** (PTFE); **up to 5,000 s** (gas-fed)
- Efficiency: **15-30%**
- Pulse rate: **1-10 Hz** typical

**Flight heritage**: First electric propulsion in space (Zond 2, 1964); EO-1 satellite (2000-2002); FalconSat-3 (2007). CU Aerospace FPPT scheduled for DUPLEX CubeSat demonstration September 2025.

**Key challenges**: Low efficiency compared to Hall/ion; electrode erosion; limited total impulse per module.

**Materials required**: PTFE propellant; tungsten or carbon electrodes; ceramic insulators; compact capacitor banks.

**Realism score**: **9/10**—Proven technology with 60+ years of flight heritage. Ideal for CubeSat-to-small-satellite scale.

---

## Concept 4: Superconducting MPD Thruster Array

**Physics principle**: High-current arc (kA range) between coaxial electrodes creates self-induced magnetic field; Lorentz force accelerates plasma. Applied-field variant uses external superconducting magnets for **5-10× efficiency improvement**.

**Configuration for saucer craft**: Central high-power MPD cluster with REBCO HTS magnets in toroidal arrangement. Disc geometry accommodates large magnet mass in central hub while thrusters fire through peripheral ports.

**Technical specifications** (2021 superconducting demonstration):
- Power: **150 kW** demonstrated; **MW-class** design target
- Thrust: **4 N at 150 kW**; up to **200 N** theoretical
- Specific impulse: **5,714 seconds** demonstrated
- Efficiency: **76.6%** at 0.56 Tesla applied field
- Exhaust velocity: **56 km/s**

**Key challenges**: Superconductor cryogenic cooling (77K for REBCO); electrode erosion at high current density (>100 A/cm²); power system mass; thermal management of multi-MW dissipation.

**Materials required**: REBCO (rare-earth barium copper oxide) tape; tungsten or thoriated tungsten cathodes; refractory anode materials (graphite, tungsten); liquid nitrogen or cryocooler systems.

**Realism score**: **8/10**—Laboratory-validated at 150 kW with superconducting magnets. EPEX on Space Flyer Unit (1995-1996) remains the only flight-tested MPD. Commonwealth Fusion's **20 Tesla at 20K** REBCO demonstration proves magnet feasibility.

---

## Concept 5: Atmospheric MHD Disc Accelerator

**Physics principle**: Cross-field MHD acceleration using Lorentz force (j×B) on ionized air or seeded propellant. The disc geometry enables **360-degree circumferential electrode placement** with uniform radial acceleration around the entire wetted surface.

**Configuration for saucer craft**: NASA MAPX-derived design with segmented Faraday electrodes embedded in hull surface, diagonal current paths for Hall neutralization, and central 2-Tesla electromagnet (water-cooled or superconducting). Air ionization via arc heater, RF discharge, or alkali metal seeding (cesium/potassium).

**Technical specifications** (NASA MAPX extrapolation):
- Power: **1.5-30 MW** (arc heater + accelerator)
- Global efficiency: **~50%** demonstrated
- Velocity increase: **80%** demonstrated in test articles
- Exhaust velocity: **15-100+ km/s** achievable
- Operating altitude: **0-80,000 ft** with air-breathing; unlimited with onboard propellant

**Key challenges**: MW-class compact power generation; air ionization energy penalty below Mach 12; electrode erosion in atmospheric plasma; aircraft integration of multi-MW systems.

**Materials required**: UHTCs (ZrB₂, HfB₂) for plasma-facing surfaces; tungsten or graphite electrodes; REBCO magnets for weight reduction; SiC power electronics.

**Why disc shape is optimal**: Subrata Roy's WEAV research at University of Florida explicitly identifies disc geometry as ideal—"A saucer-shaped Coandă effect airfoil provides greater lift than a conventional wing, and is well suited to MHD that creates a 'wind' without the need to move the entire vehicle."

**Realism score**: **7/10**—Physics validated (NASA MAPX achieved 50% efficiency); engineering integration remains TRL 3-4. DARPA PUMP program demonstrates 20-Tesla REBCO magnets for undersea MHD, proving magnet technology maturity.

---

## Concept 6: VASIMR-Style Electrodeless Plasma Propulsion

**Physics principle**: Three-stage process—helicon RF antenna ionizes propellant into cold plasma; ion cyclotron heating (ICH) raises temperature to **1-2 million Kelvin**; magnetic nozzle converts thermal energy to directed exhaust. Completely electrodeless design eliminates erosion limitations.

**Configuration for saucer craft**: Central VASIMR-type engine with superconducting magnetic nozzle; toroidal plasma confinement compatible with disc hull geometry; variable Isp for mission optimization.

**Technical specifications** (Ad Astra VX-200):
- Power: **200 kW**
- Thrust: **5.7-5.8 N**
- Specific impulse: **5,000 seconds**
- Exhaust velocity: **50 km/s**
- Efficiency: **72% ±9%**
- Power density: **>5 MW/m²**

**Key challenges**: Requires **200+ kW** nuclear or solar power source; superconducting magnet cryogenics; plasma detachment from magnetic nozzle; ISS test repeatedly delayed.

**Materials required**: REBCO superconducting coils; RF antenna materials (copper, ceramics); argon or hydrogen propellant; advanced thermal management.

**Realism score**: **7/10**—Ground-tested at 200 kW with validated performance; no flight demonstration despite decades of development. Power source remains the critical path item.

---

## Concept 7: Electrohydrodynamic Corona Discharge Array

**Physics principle**: Corona discharge ionizes air near sharp emitter electrodes; ions accelerate through electric field toward collector, transferring momentum to neutral air through collisions (ionic wind). MIT demonstrated first sustained EHD aircraft flight in 2018.

**Configuration for saucer craft**: Concentric ring emitter electrodes on upper surface with mesh collector on lower surface; wire-to-cylinder geometry maximizes thrust density. Multiple independent zones enable attitude control.

**Technical specifications**:
- Thrust-to-power: **20-100+ mN/W** demonstrated
- Maximum thrust density: **3.3 N/m² (area)**; **15 N/m³ (volume)**
- Operating voltage: **10-70 kV**
- Energy efficiency: **<2%** (kinetic conversion)
- Thrust-to-weight: **up to 17:1** achieved in optimized geometries

**Key challenges**: Atmospheric-only operation (fails in vacuum); thrust degrades with altitude (26 mN/W at 1 atm → 0.5 mN/W at 20 km); very low overall efficiency; ozone generation.

**Materials required**: Tungsten or stainless steel emitter wires; aluminum mesh collectors; high-voltage ceramic insulators; lightweight dielectric structures.

**Realism score**: **6/10**—Physics proven and flight-demonstrated; engineering limitations (atmospheric-only, low efficiency) severely constrain practical applications. Best suited for low-altitude loitering platforms.

---

## Concept 8: Laser-Ablation Beamed Energy Propulsion

**Physics principle**: Ground-based pulsed laser (CO₂ at 10.6 μm) strikes parabolic reflector on vehicle, focusing energy to heat air to **~30,000°F**, creating explosive plasma detonation at **20-28 Hz** for thrust. Leik Myrabo's Lightcraft achieved **71-meter altitude record** in October 2000.

**Configuration for saucer craft**: Parabolic lower surface reflector optimized for laser wavelength; annular detonation chamber around perimeter; disc geometry provides natural focal surface.

**Technical specifications** (White Sands demonstrations):
- Laser power: **9-10 kW pulsed**
- Vehicle mass: **50.6 grams** (record altitude vehicle)
- Altitude achieved: **71 meters** (233 feet)
- Coupling coefficient: **56 μN/W** demonstrated
- Theoretical Isp: **1,000-3,660+ seconds**

**Key challenges**: Requires massive ground infrastructure; atmospheric beam propagation limits; tracking over long distances; craft size limited by beam power; spin stabilization required.

**Materials required**: Aluminum or copper parabolic reflector; ablative propellant surface; high-temperature structural materials; spin motor (single moving part—could use reaction wheels instead).

**Realism score**: **5/10**—Physics fully validated with flight demonstrations; **engineering scale-up** from 10 kW to proposed 100+ GW for orbital delivery remains impractical. Most viable for small-scale demonstrations.

---

## Concept 9: Plasma Window Atmospheric Interface

**Physics principle**: DC plasma arc at **~12,000 K** creates stabilized barrier separating vacuum from atmosphere without solid surfaces. At 12,000 K, plasma density is 1/40 atmospheric while matching pressure, creating viscous seal.

**Configuration for saucer craft**: Ring plasma window around disc perimeter for drag reduction and thermal protection; enables vacuum-rated propulsion systems to operate through atmospheric transition.

**Technical specifications** (Brookhaven demonstration):
- Pressure differential: **>2.5 atmospheres** sustained
- Aperture tested: **3mm diameter**
- Power requirement: **~20 kW per inch of diameter**
- Pressure reduction factor: **228.6×** vs. differential pumping

**Key challenges**: Power scaling to spacecraft-sized apertures; plasma stability at high dynamic pressure; integration with propulsion system exhaust.

**Applications for saucer craft**: Combined with MHD or ion propulsion for multi-regime operation; reentry thermal protection; charged particle beam transmission.

**Realism score**: **5/10**—Laboratory-demonstrated at small scale; scaling to spacecraft apertures unvalidated. Most promising as enabling technology rather than primary propulsion.

---

## Concept 10: Solar Sail with Reflectance Control

**Physics principle**: Solar radiation pressure (~9 μN/m² at 1 AU) on highly reflective surfaces provides continuous propellant-free thrust. JAXA's IKAROS demonstrated LCD panels for attitude control via reflectance modulation—no moving parts.

**Configuration for saucer craft**: Deployable disc-shaped sail with embedded thin-film solar cells (IKAROS heritage); LCD reflectance panels for attitude control; compatible with disc structural geometry.

**Technical specifications** (IKAROS/LightSail heritage):
- Sail areal density: **~10 g/m²**
- Thrust: **~1 mN per 200 m²** at 1 AU
- Specific impulse: **Infinite** (propellant-free)
- Attitude control: **80 LCD panels** demonstrated reflectance modulation

**Key challenges**: Extremely low thrust; requires large sail area; deployment complexity; solar pressure decreases with square of distance from Sun.

**Realism score**: **9/10** for deep space; **3/10** for near-Earth or maneuvering applications due to low thrust. NASA Solar Cruiser (1,200+ m²) planned for 2025+ deployment.

---

## Concept 11: Field-Reversed Configuration Plasma Thruster

**Physics principle**: Self-organized plasma torus with reversed magnetic field provides compact, high-beta confinement. FRC plasmoids can be formed and ejected for propulsion without electrode contact.

**Configuration for saucer craft**: Toroidal FRC formation chamber in central disc hub; magnetic nozzle for plasmoid ejection; axisymmetric geometry matches disc structure.

**Technical specifications** (theoretical/early experimental):
- Projected specific impulse: **2,000-10,000 seconds**
- Projected efficiency: **50-70%**
- Plasma density: **10¹⁹-10²¹ m⁻³**
- Confinement: **Self-organized field reversal**

**Key challenges**: Plasmoid stability during acceleration; magnetic nozzle efficiency; plasma detachment; TRL 2-3 for propulsion application.

**Realism score**: **5/10**—Plasma physics validated in fusion research (TAE Technologies, Helion); propulsion application remains early-stage. Promising long-term candidate.

---

## Concept 12: Piezoelectric Structural Actuator Array

**Physics principle**: Distributed piezoelectric elements (PZT, PMN-PT) embedded in structure create acoustic/vibrational forces for attitude control and potentially micro-propulsion through momentum transfer.

**Configuration for saucer craft**: Hull-integrated piezoelectric tiles operating in coordinated phase patterns; combined with EHD for atmospheric operation.

**Technical specifications**:
- Piezoelectric coefficient (PMN-PT): **~2,000 pC/N**
- Operating frequency: **kHz to MHz range**
- Force generation: **μN to mN** scale
- Power: **Watts to hundreds of watts**

**Key challenges**: Very low thrust; complex control algorithms; structural fatigue; thermal limitations.

**Realism score**: **3/10**—Well-understood material physics; propulsion application highly limited. Best suited for fine attitude control rather than primary propulsion.

---

## Concept 13: Dielectric Barrier Discharge Flow Control

**Physics principle**: AC-driven plasma discharge between surface electrodes and buried ground plane creates body force in atmospheric flow; demonstrated **45-68% skin friction reduction** in turbulent boundary layers.

**Configuration for saucer craft**: Hull-surface DBD actuators for drag reduction and virtual surface shaping; enables reduced power requirement for primary propulsion; no moving parts.

**Technical specifications**:
- Skin friction reduction: **30-68%** demonstrated
- Power consumption: **10-100 W/m²** typical
- Operating voltage: **5-20 kV AC** at **1-10 kHz**
- Thrust augmentation: Indirect through drag reduction

**Key challenges**: Atmospheric-only; modest direct thrust; ozone generation; electrode degradation.

**Realism score**: **7/10** for drag reduction integration; **4/10** as primary propulsion. Most valuable as **augmentation** to other propulsion systems.

---

## Concept 14: Passive Electrostatic Levitation (Validated Physics)

**Physics principle**: The Biefeld-Brown effect produces measurable thrust on asymmetric capacitors—however, this is **ion wind (electrohydrodynamics)**, not anti-gravity as originally claimed. High-voltage ionization creates directed momentum transfer.

**Configuration for saucer craft**: Asymmetric capacitor arrays with sharp emitter surfaces; essentially optimized EHD with capacitor geometry.

**Technical specifications**:
- Thrust mechanism: **Ion wind** (confirmed by Army Research Lab 2002)
- Operating voltage: **25,000-200,000 V**
- Atmospheric-only: Effects diminish dramatically in vacuum
- Efficiency: Very low (<1%)

**Key challenges**: Identical to EHD limitations; often misrepresented as exotic physics.

**Realism score**: **4/10**—Real thrust from understood physics, but very inefficient. Historical interest exceeds practical utility.

---

## Concept 15: MHD Reentry Power Generation/Braking

**Physics principle**: High-enthalpy reentry plasma flow through crossed magnetic fields generates electric power while creating drag force. Dual-use system provides both deceleration and power for other spacecraft systems.

**Configuration for saucer craft**: Surface MHD generators on leading edge of disc; recovered power feeds plasma actuators and vehicle systems; disc geometry provides large cross-section for energy capture.

**Technical specifications** (DIA report projections):
- Power extraction: **MW-class** from reentry plasma
- Drag augmentation: **2-5× baseline** aerodynamic drag
- Operating regime: **Mach 10+** reentry conditions
- Plasma conductivity: **~10³-10⁴ S/m** in shock layer

**Key challenges**: Extreme thermal environment; magnet protection; power conditioning in harsh environment; TRL 2-3.

**Realism score**: **5/10**—Physics validated in ground facilities; flight demonstration lacking. Most relevant for **atmospheric entry** rather than cruise propulsion.

---

## Debunked and non-viable concepts excluded from ranking

Several widely discussed propulsion concepts fail physics validation and should not be pursued:

**EmDrive/RF Cavity Thrusters**: Dresden University's 2021 experiments using battery-isolated thrust balances found **zero thrust** within measurement accuracy—3+ orders of magnitude below claimed effects. NASA Eagleworks' earlier positive results were artifacts from thermal drift in mounting hardware. Conservation of momentum violation makes reactionless thrust physically impossible.

**Mach Effect Thrusters**: Same Dresden research identified measured forces as **vibrational artifacts**, not real thrust. Theoretical derivation inconsistent with Einstein's field equations.

**Quantum Vacuum Plasma Thrusters**: Sean Carroll (Caltech) and other physicists note "quantum vacuum virtual plasma" is not a meaningful physics concept. All claimed effects explained by experimental error.

**Podkletnov Gravity Shielding**: Multiple well-funded replication attempts (Toronto, Sheffield, NASA, Tajmar) produced **null results**. Original claims likely instrumentation artifacts.

**Pais "Inertial Mass Reduction" Patents**: Navy testing over 3 years (~$500,000) concluded **"The Pais Effect could not be proven."** Patents expired for non-payment; considered pseudoscience.

**Alcubierre Warp Drive**: Mathematically consistent with general relativity but requires **exotic matter with negative energy density** that has never been observed and may not exist.

---

## Implementation roadmap by timeline

### Near-term (buildable now, 0-5 years)
Deploy **Hall thruster arrays** (Concept 1) and **ion engine clusters** (Concept 2) for space operation. Both are TRL 9 with extensive flight heritage. Integrate **pulsed plasma thrusters** (Concept 3) for attitude control. Add **solar sail elements** (Concept 10) for propellant-free cruise. **Estimated development cost**: $50-200M for complete saucer-scale system.

### Mid-term (advanced development, 5-15 years)
Develop **superconducting MPD thrusters** (Concept 4) using REBCO magnets proven in fusion and DARPA PUMP programs. Integrate **atmospheric MHD** (Concept 5) for dual-regime operation. Add **DBD flow control** (Concept 13) for drag reduction. Requires **compact nuclear power** (Kilopower-derived, 40+ kWe). **Estimated development cost**: $500M-2B.

### Far-term (physics validation required, 15-25+ years)
**FRC plasma thrusters** (Concept 11) depend on fusion research progress. **VASIMR-scale systems** (Concept 6) await compact nuclear reactors >200 kW. Full atmospheric/space transition capability requires integrated **plasma window** (Concept 9) technology and MW-class power. **Estimated development cost**: $2-10B.

---

## Materials and power requirements summary

The critical enabling technologies across all viable concepts are **superconducting magnets** (REBCO achieving 20+ Tesla), **compact nuclear power** (Kilopower at TRL 5 providing 1-10 kWe, scalable), and **high-temperature plasma-facing materials** (UHTCs like ZrB₂ surviving >2000°C). Power electronics must use **radiation-resistant SiC/GaN** semiconductors for space operation.

| System | Power Required | Magnet Field | Temperature Rating |
|--------|----------------|--------------|-------------------|
| Hall Array | 0.5-100 kW | 0.01-0.05 T | <300°C |
| Ion Cluster | 0.6-7.4 kW | N/A | <300°C |
| MPD | 100 kW-30 MW | 0.5-2 T | <500°C electrodes |
| Atmospheric MHD | 1-30 MW | 2-20 T | >2000°C surfaces |
| VASIMR | 200+ kW | 1-2 T (SC) | Cryogenic coils |

The saucer configuration provides unique advantages for electromagnetic propulsion—axisymmetric geometry enables uniform field distribution, 360° thrust vectoring through electrode differential control, and integrated plasma sheath management around the entire perimeter. Historical disc aircraft (V-173, EKIP) validate aerodynamic viability, while NASA MAPX experiments confirm MHD accelerator physics. The path forward combines flight-proven electric propulsion for space operation with emerging MHD technology for atmospheric capability, avoiding both pseudoscientific claims and physically impossible exotic concepts.