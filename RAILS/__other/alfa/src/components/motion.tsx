'use client'

/*
 * Bevegelsessett — "fully immersive, still honest".
 * Lenis (rolig rull) + framer-motion (parallaks, maskerte ord, tellere, marquee,
 * magnetiske knapper, markør). Alt respekterer prefers-reduced-motion.
 */

import {
  motion,
  useScroll,
  useTransform,
  useReducedMotion,
  useInView,
  animate,
  useMotionValue,
  useSpring,
} from 'framer-motion'
import Lenis from 'lenis'
import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type CSSProperties,
} from 'react'

const EASE = [0.2, 0.6, 0.2, 1] as const

/* — Rolig rull — */
export function SmoothScroll({ children }: { children: ReactNode }) {
  const reduced = useReducedMotion()
  useEffect(() => {
    if (reduced) return
    const lenis = new Lenis({ duration: 1.15, smoothWheel: true })
    let raf = 0
    const loop = (t: number) => {
      lenis.raf(t)
      raf = requestAnimationFrame(loop)
    }
    raf = requestAnimationFrame(loop)
    return () => {
      cancelAnimationFrame(raf)
      lenis.destroy()
    }
  }, [reduced])
  return <>{children}</>
}

/* — Inngang: stige + bli skarp — */
export function Reveal({
  children,
  delay = 0,
  className,
  style,
}: {
  children: ReactNode
  delay?: number
  className?: string
  style?: CSSProperties
}) {
  const reduced = useReducedMotion()
  if (reduced) return <div className={className}>{children}</div>
  return (
    <motion.div
      className={className}
      style={style}
      initial={{ opacity: 0, y: 26, filter: 'blur(8px)' }}
      whileInView={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
      viewport={{ once: true, margin: '0px 0px -8% 0px' }}
      transition={{ duration: 0.85, ease: EASE, delay }}
    >
      {children}
    </motion.div>
  )
}

/* — Ordmasker: hver ord stiger opp bak sin egen maske — */
export function WordReveal({
  text,
  className,
  delay = 0,
  stagger = 0.055,
}: {
  text: string
  className?: string
  delay?: number
  stagger?: number
}) {
  const reduced = useReducedMotion()
  const ref = useRef<HTMLSpanElement>(null)
  // Observer den YTRE, uklipte span-en: et element som er fullt klippet
  // av sin egen overflow:hidden-maske rapporterer aldri "intersecting".
  const inView = useInView(ref, { once: true, margin: '0px 0px -6% 0px' })
  const words = text.split(' ')
  if (reduced) return <span className={className}>{text}</span>
  return (
    <span ref={ref} className={className} aria-label={text} role="text">
      {words.map((w, i) => (
        <span key={i} className="wr-mask" aria-hidden="true">
          <motion.span
            className="wr-word"
            initial={{ y: '112%' }}
            animate={inView ? { y: '0%' } : { y: '112%' }}
            transition={{ duration: 0.75, ease: EASE, delay: delay + i * stagger }}
          >
            {w}
            {i < words.length - 1 ? '\u00A0' : ''}
          </motion.span>
        </span>
      ))}
    </span>
  )
}

/* — Parallaks: bildet puster i sin ramme — */
export function Parallax({
  src,
  alt,
  className,
  amount = 10,
}: {
  src: string
  alt: string
  className?: string
  amount?: number
}) {
  const ref = useRef<HTMLDivElement>(null)
  const reduced = useReducedMotion()
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start end', 'end start'],
  })
  const y = useTransform(scrollYProgress, [0, 1], [`-${amount}%`, `${amount}%`])
  return (
    <div ref={ref} className={`pl-frame ${className ?? ''}`}>
      <motion.div className="pl-inner" style={reduced ? undefined : { y }}>
        <img src={src} alt={alt} />
      </motion.div>
    </div>
  )
}

/* — Marquee: kontinuerlig, respektfullt — */
export function Marquee({
  children,
  duration = 26,
  className,
}: {
  children: ReactNode
  duration?: number
  className?: string
}) {
  const reduced = useReducedMotion()
  const row = (
    <div className="mq-row">
      {children}
      {children}
    </div>
  )
  return (
    <div className={`mq ${className ?? ''}`} aria-hidden="false">
      {reduced ? (
        <div className="mq-row">{children}</div>
      ) : (
        <motion.div
          className="mq-row mq-anim"
          style={{ animationDuration: `${duration}s` }}
        >
          {children}
          {children}
        </motion.div>
      )}
    </div>
  )
}

/* — Teller: tallet som vokser når det ses — */
export function Counter({
  to,
  suffix = '',
  className,
}: {
  to: number
  suffix?: string
  className?: string
}) {
  const ref = useRef<HTMLSpanElement>(null)
  const inView = useInView(ref, { once: true, margin: '0px 0px -10% 0px' })
  const reduced = useReducedMotion()
  const [val, setVal] = useState(0)
  useEffect(() => {
    if (!inView) return
    if (reduced) {
      setVal(to)
      return
    }
    const ctrl = animate(0, to, {
      duration: 1.6,
      ease: EASE,
      onUpdate: (v) => setVal(Math.round(v)),
    })
    return () => ctrl.stop()
  }, [inView, to, reduced])
  return (
    <span ref={ref} className={className}>
      {val}
      {suffix}
    </span>
  )
}

/* — Magnetisk knapp: følger hånden en stund, finner hjem — */
export function Magnetic({
  children,
  strength = 0.28,
  className,
}: {
  children: ReactNode
  strength?: number
  className?: string
}) {
  const ref = useRef<HTMLDivElement>(null)
  const reduced = useReducedMotion()
  const x = useMotionValue(0)
  const y = useMotionValue(0)
  const sx = useSpring(x, { stiffness: 220, damping: 18 })
  const sy = useSpring(y, { stiffness: 220, damping: 18 })
  return (
    <motion.div
      ref={ref}
      className={className}
      style={reduced ? undefined : { x: sx, y: sy, display: 'inline-block' }}
      onMouseMove={(e) => {
        if (reduced || !ref.current) return
        const r = ref.current.getBoundingClientRect()
        x.set((e.clientX - (r.left + r.width / 2)) * strength)
        y.set((e.clientY - (r.top + r.height / 2)) * strength)
      }}
      onMouseLeave={() => {
        x.set(0)
        y.set(0)
      }}
    >
      {children}
    </motion.div>
  )
}

/* — Markør: liten prikk med myk hale, kun ved peker — */
export function Cursor() {
  const reduced = useReducedMotion()
  const dot = useRef<HTMLDivElement>(null)
  const ring = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (reduced) return
    if (typeof window === 'undefined') return
    if (!window.matchMedia('(pointer: fine)').matches) return
    let mx = -100, my = -100, rx = -100, ry = -100, raf = 0
    const move = (e: MouseEvent) => {
      mx = e.clientX
      my = e.clientY
      const t = e.target as HTMLElement | null
      const hot = !!t?.closest('a, button, [data-cursor]')
      dot.current?.classList.toggle('cur-hot', hot)
      ring.current?.classList.toggle('cur-hot', hot)
    }
    const loop = () => {
      rx += (mx - rx) * 0.16
      ry += (my - ry) * 0.16
      if (dot.current) dot.current.style.transform = `translate(${mx}px, ${my}px)`
      if (ring.current) ring.current.style.transform = `translate(${rx}px, ${ry}px)`
      raf = requestAnimationFrame(loop)
    }
    window.addEventListener('mousemove', move, { passive: true })
    raf = requestAnimationFrame(loop)
    return () => {
      window.removeEventListener('mousemove', move)
      cancelAnimationFrame(raf)
    }
  }, [reduced])
  if (reduced) return null
  return (
    <>
      <div ref={dot} className="cur-dot" aria-hidden="true" />
      <div ref={ring} className="cur-ring" aria-hidden="true" />
    </>
  )
}
