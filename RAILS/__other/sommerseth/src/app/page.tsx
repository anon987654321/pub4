import Link from "next/link";
import { SommersethMark } from "@/components/marks";
import {
  SmoothScroll,
  Reveal,
  WordReveal,
  Parallax,
  Counter,
  Magnetic,
  Cursor,
} from "@/components/motion";
import styles from "./sommerseth.module.css";

const nav = [
  { href: "#eiendommene", label: "Eiendommene" },
  { href: "#om-oss", label: "Om oss" },
  { href: "#verdier", label: "Verdier" },
];

export default function Sommerseth() {
  return (
    <SmoothScroll>
      <div className={styles.page}>
        <Cursor />

        <header className={styles.nav}>
          <Link href="/" className={styles.brand}>
            <SommersethMark size={30} />
            <span>Sommerseth&nbsp;Eiendom</span>
          </Link>
          <nav className={styles.links} aria-label="Hovedmeny">
            {nav.map((n) => (
              <a key={n.href} href={n.href}>
                {n.label}
              </a>
            ))}
            <a href="#kontakt" className={styles.cta}>
              Kontakt oss
            </a>
          </nav>
        </header>

        <main>
          {/* ——— Hero ——— */}
          <section className={styles.hero}>
            <Reveal>
              <p className={styles.kicker}>
                Familieeid utleie · Fyllingsdalen · siden 2021
              </p>
            </Reveal>
            <h1 className={styles.display}>
              <WordReveal text="Hjem er et" />{" "}
              <em>
                <WordReveal text="løfte vi holder." delay={0.28} />
              </em>
            </h1>
            <Reveal delay={0.5}>
              <p className={styles.lead}>
                Sommerseth Eiendom er en familie som leier ut, drifter og steller
                hjem i Fyllingsdalen. Vi kjenner hver bolig sine særpreg — og hver
                leietaker sitt navn.
              </p>
              <div className={styles.heroCtas}>
                <Magnetic>
                  <a className={styles.primary} href="#eiendommene">
                    Se eiendommene <span aria-hidden="true">↓</span>
                  </a>
                </Magnetic>
                <a className={styles.quiet} href="#om-oss">
                  Møt familien
                </a>
              </div>
            </Reveal>
          </section>

          <Reveal>
            <figure className={styles.heroFig}>
              <Parallax
                src="/images/som-hero.jpg"
                alt="Rødt trehus ved fjorden i kveldslys, med fjell i bakgrunnen"
              />
              <figcaption>
                Fyllingsdalen i kveldslys — der husene våre står.
              </figcaption>
            </figure>
          </Reveal>

          {/* ——— Faktastripping ——— */}
          <Reveal>
            <ul className={styles.facts}>
              <li>
                <strong>
                  <Counter to={2021} />
                </strong>
                <span>etablert av familien</span>
              </li>
              <li>
                <strong>
                  <Counter to={100} suffix="&nbsp;%" />
                </strong>
                <span>familieeid og lokalt drevet</span>
              </li>
              <li>
                <strong>Fyllingsdalen</strong>
                <span>
                  ti minutter fra sentrum, ett skritt fra Lyderhorn
                </span>
              </li>
            </ul>
          </Reveal>

          {/* ——— Om oss ——— */}
          <section id="om-oss" className={styles.split}>
            <Reveal className={styles.splitText}>
              <p className={styles.label}>Om oss</p>
              <h2 className={styles.h2}>
                Ingen meglerkjede. <em>Bare en familie.</em>
              </h2>
              <p>
                Sommerseth Eiendom startet i 2021 med én bolig og en enkel tanke:
                utleie skal føles trygg for begge parter. Vi eier hjemmene vi
                forvalter, og svarer for dem med eget navn. Det gjør avstandene
                korte — både de på kartet og de i samtalen.
              </p>
              <p>
                Vi fikser før det blir et problem, ringer tilbake samme dag og
                følger med på husene slik man følger med på et familiemedlem.
                Leietakerne hos oss blir boende i gjennomsnitt i flere år — mange
                lenge nok til at barna deres starter i barnehagen her.
              </p>
            </Reveal>
            <Reveal delay={0.12} className={styles.splitFig}>
              <Parallax
                src="/images/som-interior.jpg"
                alt="Lyst stuehjørne med sofa, teppe og plante i ettermiddagssol"
                amount={8}
              />
            </Reveal>
          </section>

          {/* ——— Eiendommene ——— */}
          <section id="eiendommene" className={styles.props}>
            <Reveal>
              <p className={styles.label}>Eiendommene</p>
              <h2 className={styles.h2}>
                Boliger som bærer preg <em>av stedet.</em>
              </h2>
            </Reveal>
            <Reveal delay={0.1}>
              <div className={styles.wideFig}>
                <Parallax
                  src="/images/som-houses.jpg"
                  alt="Rekke av norske trehus i hvitt, gult og rødt under fjellet"
                />
              </div>
            </Reveal>
            <div className={styles.rows}>
              {[
                {
                  n: "01",
                  t: "Eneboliger og rekkehus",
                  d: "Trehus med hage og rom for hele familien.",
                },
                {
                  n: "02",
                  t: "Leiligheter",
                  d: "Lyse hjem med ett til fire soverom, klare for innflytting.",
                },
                {
                  n: "03",
                  t: "Langtidsleie",
                  d: "Trygge kontrakter og forutsigbarhet — for begge parter.",
                },
              ].map((r, i) => (
                <Reveal key={r.n} delay={i * 0.09}>
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

          {/* ——— Verdier ——— */}
          <section id="verdier" className={styles.values}>
            {[
              {
                t: "Nærhet",
                d: "Vi bor i samme bydel som hjemmene vi leier ut. Det skal merkes i responstid, i vedlikehold og i at vi alltid kan møte deg ansikt til ansikt.",
              },
              {
                t: "Tillit",
                d: "Åpen kontrakt, åpen regning og en telefon du faktisk når. Tillit er ikke en verdi hos oss — det er selve driftsformen.",
              },
              {
                t: "Enkelhet",
                d: "Én kontakt, én avtale, én løsning som fungerer. Vi fjerner det som er unødvendig, slik at hjemmet kan stå igjen i fred.",
              },
            ].map((v, i) => (
              <Reveal key={v.t} delay={i * 0.1} className={styles.value}>
                <h3>{v.t}</h3>
                <p>{v.d}</p>
              </Reveal>
            ))}
          </section>

          {/* ——— Kontakt ——— */}
          <section id="kontakt" className={styles.contact}>
            <Reveal>
              <p className={styles.label}>Kontakt</p>
              <h2 className={styles.display2}>
                <WordReveal text="Si" />{" "}
                <em>
                  <WordReveal text="hei." delay={0.2} />
                </em>
              </h2>
              <div className={styles.contactRows}>
                <a href="mailto:hei@sommerseth-eiendom.no">
                  hei@sommerseth-eiendom.no
                </a>
                <a href="tel:+4755902021">+47 55 90 20 21</a>
                <span>Fyllingsdalen, Bergen</span>
              </div>
              <p className={styles.contactNote}>
                Vi svarer på henvendelser samme virkedag — som regel raskere.
              </p>
            </Reveal>
          </section>
        </main>

        <footer className={styles.footer}>
          <div className={styles.brand}>
            <SommersethMark size={26} />
            <span>Sommerseth&nbsp;Eiendom</span>
          </div>
          <span>© 2026 Sommerseth Eiendom AS · Fyllingsdalen, Bergen</span>
          {/* Søstermerket — planlagt domene, ikke kjøpt ennå */}
          <a href="https://alfabergen.no" className={styles.sister}>
            Søstermerket vårt i bybildet: Alfa Bergen{" "}
            <span aria-hidden="true">↗</span>
          </a>
        </footer>
      </div>
    </SmoothScroll>
  );
}
