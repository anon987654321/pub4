import Link from "next/link";
import { AlfaMark } from "@/components/marks";
import {
  SmoothScroll,
  Reveal,
  WordReveal,
  Parallax,
  Marquee,
  Magnetic,
  Cursor,
} from "@/components/motion";
import styles from "./alfa.module.css";

const nav = [
  { href: "#historie", label: "Historie" },
  { href: "#tjenester", label: "Tjenester" },
  { href: "#bygget", label: "Bygget" },
];

export default function Alfa() {
  return (
    <SmoothScroll>
      <div className={styles.page}>
        <Cursor />
        <div className={styles.edgeL} aria-hidden="true" />
        <div className={styles.edgeR} aria-hidden="true" />

        <header className={styles.nav}>
          <Link href="/" className={styles.brand}>
            <AlfaMark size={28} />
            <span>Alfa&nbsp;Bergen</span>
          </Link>
          <nav className={styles.links} aria-label="Hovedmeny">
            {nav.map((n) => (
              <a key={n.href} href={n.href}>
                {n.label}
              </a>
            ))}
            <a href="#kontakt" className={styles.cta}>
              Kontakt
            </a>
          </nav>
        </header>

        <main>
          {/* ——— Hero ——— */}
          <section className={styles.hero}>
            <Reveal>
              <p className={styles.kicker}>Eiendomsdrift · Bergen · siden 2006</p>
            </Reveal>
            <h1 className={styles.display}>
              <WordReveal text="Fra flytting til" />{" "}
              <em>
                <WordReveal text="forvaltning." delay={0.32} />
              </em>
            </h1>
            <Reveal delay={0.5}>
              <p className={styles.lead}>
                Alfa Bergen begynte som et flyttebyrå i 2006. I dag driver,
                forvalter og vedlikeholder vi eiendommer i hele Bergen — med samme
                presisjon som da vi bar de første kassene på trappa.
              </p>
              <div className={styles.heroCtas}>
                <Magnetic>
                  <a className={styles.primary} href="#tjenester">
                    Se tjenestene <span aria-hidden="true">↓</span>
                  </a>
                </Magnetic>
                <a className={styles.quiet} href="#historie">
                  Les historien
                </a>
              </div>
            </Reveal>
          </section>

          <Reveal>
            <div className={styles.heroFig}>
              <Parallax
                src="/images/alfa-hero.jpg"
                alt="Mørk trebekledd bygning med skarp geometri under grå himmel"
              />
            </div>
          </Reveal>

          <Reveal>
            <div className={styles.metaRow}>
              <span>Møllendalsveien</span>
              <span>Bergen by</span>
              <span>Est. 2006</span>
            </div>
          </Reveal>

          {/* ——— Arbeidsfelt (marquee) ——— */}
          <div className={styles.strip}>
            <Marquee duration={30}>
              {[
                "Flytting",
                "Forvaltning",
                "Drift",
                "Vedlikehold",
                "Utleie",
              ].map((w) => (
                <span key={w} className={styles.stripItem}>
                  {w} <i aria-hidden="true">—</i>
                </span>
              ))}
            </Marquee>
          </div>

          {/* ——— 01 Historie ——— */}
          <section id="historie" className={styles.section}>
            <Reveal className={styles.sectionHead}>
              <span className={styles.no}>01</span>
              <h2 className={styles.h2}>Nitten år med tunge løft.</h2>
            </Reveal>
            <div className={styles.twoCol}>
              <Reveal>
                <p>
                  Det startet med én varebil og en familie som aldri var redd for
                  å jobbe. Flyttebyrået vokste — ikke fordi vi lovet mye, men
                  fordi vi møtte opp. Kontrakt for kontrakt ble tilliten til
                  virksomheten større enn lastebilen vår.
                </p>
                <p>
                  Da kundene begynte å spørre om vi også kunne drifte bygningene
                  de flyttet fra, svarte vi ja. Så vokste det stille og helt
                  naturlig: fra flytting til forvaltning, fra kasser til
                  kontrakter, fra én varebil til en hel beredskap.
                </p>
              </Reveal>
              <Reveal delay={0.12}>
                <figure className={styles.colFig}>
                  <Parallax
                    src="/images/alfa-city.jpg"
                    alt="Bergens havnefront i blå timen, med fjell bak"
                    amount={8}
                  />
                  <figcaption>Bergen i blå timen — arbeidsområdet vårt.</figcaption>
                </figure>
              </Reveal>
            </div>
          </section>

          {/* ——— 02 Tjenester ——— */}
          <section id="tjenester" className={styles.section}>
            <Reveal className={styles.sectionHead}>
              <span className={styles.no}>02</span>
              <h2 className={styles.h2}>Fire felter. Én standard.</h2>
            </Reveal>
            <div className={styles.rows}>
              {[
                {
                  n: "01",
                  t: "Flytting og transport",
                  d: "Der vi startet. Forberedt, pakket og levert — uten drama.",
                },
                {
                  n: "02",
                  t: "Eiendomsforvaltning",
                  d: "Kontrakter, leietakere og regnskap — ryddig ført, alltid synlig for eier.",
                },
                {
                  n: "03",
                  t: "Drift og vedlikehold",
                  d: "Beredskap hele døgnet. Vi fikser det før det blir et krav.",
                },
                {
                  n: "04",
                  t: "Utleie",
                  d: "Boliger stilt frem ærlig, leid ut til mennesker som blir boende.",
                },
              ].map((r, i) => (
                <Reveal key={r.n} delay={i * 0.08}>
                  <a href="#kontakt" className={styles.row} data-cursor>
                    <span className={styles.rowN}>{r.n}</span>
                    <span className={styles.rowT}>{r.t}</span>
                    <span className={styles.rowD}>{r.d}</span>
                    <span className={styles.rowA} aria-hidden="true">
                      →
                    </span>
                  </a>
                </Reveal>
              ))}
            </div>
          </section>

          {/* ——— 03 Bygget ——— */}
          <section id="bygget" className={styles.section}>
            <Reveal className={styles.sectionHead}>
              <span className={styles.no}>03</span>
              <h2 className={styles.h2}>Et hus med flere liv.</h2>
            </Reveal>
            <div className={styles.twoCol}>
              <Reveal>
                <p>
                  Hovedkvarteret på Møllendalsveien har levd flere liv — først som
                  hotell, så kontor, nå som base for en familie som aldri har
                  vært redd for å ta på seg hansker. Treverket, betongen og
                  messingdetaljene i fasaden forteller historien bedre enn vi kan.
                </p>
                <p>
                  Vi behandler bygninger slik vi behandler kontrakter: med
                  respekt for det som står der fra før, og med en plan for det som
                  kommer. Det er hele filosofien bak Alfa Bergen.
                </p>
              </Reveal>
              <Reveal delay={0.12}>
                <figure className={styles.colFig}>
                  <Parallax
                    src="/images/alfa-detail.jpg"
                    alt="Detalj av svart timber, betong og innfelt messinglys"
                    amount={8}
                  />
                  <figcaption>
                    Materialestandarden: tre, betong, messing.
                  </figcaption>
                </figure>
              </Reveal>
            </div>
          </section>

          {/* ——— 04 Kontakt ——— */}
          <section id="kontakt" className={styles.contact}>
            <Reveal>
              <span className={styles.no}>04</span>
              <h2 className={styles.display2}>
                <WordReveal text="Snakk" />{" "}
                <em>
                  <WordReveal text="med oss." delay={0.2} />
                </em>
              </h2>
              <div className={styles.contactRows}>
                <a href="mailto:post@alfabergen.no">post@alfabergen.no</a>
                <a href="tel:+4755302010">+47 55 30 20 10</a>
                <span>Møllendalsveien · Bergen</span>
              </div>
              <p className={styles.contactNote}>
                Kontoret er bemannet hverdager 08–16. Beredskapen er det ikke.
              </p>
            </Reveal>
          </section>
        </main>

        <footer className={styles.footer}>
          <div className={styles.brand}>
            <AlfaMark size={24} />
            <span>Alfa&nbsp;Bergen</span>
          </div>
          <span>© 2026 Alfa Bergen AS · Bergen</span>
          {/* Søstermerket — planlagt domene, ikke kjøpt ennå */}
          <a href="https://sommerseth.no" className={styles.sister}>
            Søstermerket: Sommerseth Eiendom <span aria-hidden="true">↗</span>
          </a>
        </footer>
      </div>
    </SmoothScroll>
  );
}
