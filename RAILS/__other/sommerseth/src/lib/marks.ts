/*
 * Bergen-snittet v1 — parametrisk merkesystem for Sommerseth Eiendom og Alfa Bergen.
 *
 * Én konstruksjonsgrammatikk, to merker:
 *   Horisont (y=38) · taklinje (stigning RISE over halv bredde) · halvsirkel (r).
 *   Sommerseth: midnattssolen (halvsirkel r=SUN_R) født fra setertakets fot.
 *   Alfa:       A-scråtaket med tilsvarende halvsirkel som inngangsdør (r=DOOR_R).
 *
 * Alle kurver beregnes fra konstantene under — ingenting er tegnet for hånd.
 * scripts/gen-marks.mjs leser de samme konstantene og genererer favicons.
 */

export const SYS = {
  GRID: 48,
  STROKE: 3.2,
  HORIZON_Y: 38,
  RISE: 25,
  SUN_R: 6.5,
  DOOR_R: 5.2, // 0.8 × SUN_R
} as const

/* Halvsirkel over horisonten (flat side ned) */
function halfDisc(cx: number, r: number): string {
  const y = SYS.HORIZON_Y
  return `M${cx - r} ${y} A${r} ${r} 0 0 1 ${cx + r} ${y} Z`
}

/* Taklinje: fot (x1,y) → vind (apex) → fot (x2,y) */
function roofline(x1: number, apexX: number, x2: number): string {
  const y = SYS.HORIZON_Y
  const apexY = y - SYS.RISE
  return `M${x1} ${y} L${apexX} ${apexY} L${x2} ${y}`
}

/* — Sommerseth: solen ved takets venstre fot, taket stiger videre mot høyre — */
export const SOMMERSETH = {
  horizon: 'M4 38 H44',
  sun: halfDisc(15, SYS.SUN_R), // senter (15,38) = takets venstre fot
  roof: roofline(15, 30, 45), // fot ved solens senter, vind (30,13)
}

/* — Alfa: A-scråtak, symmetrisk, med halvsirkeldør i midten — */
export const ALFA = {
  horizon: 'M4 38 H44',
  roof: roofline(8, 24, 40), // halv bredde 16, stigning 25 → samme vinkel
  door: halfDisc(24, SYS.DOOR_R),
}

/* Vinkelen i systemet (deg) — kun til dokumentasjon/verifisering */
export const ROOF_ANGLE_DEG =
  Math.round((Math.atan(SYS.RISE / 16) * 180) / Math.PI * 10) / 10 // ≈ 57.4°
