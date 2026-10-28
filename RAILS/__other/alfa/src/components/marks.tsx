/*
 * Merker — Bergen-snittet v1 (se src/lib/marks.ts).
 * Ordmerket bærer identiteten; merkene er parametriske ledsagere.
 */
import { SOMMERSETH, ALFA, SYS } from '@/lib/marks'

type MarkProps = {
  size?: number
  className?: string
  signal?: string
}

export function SommersethMark({ size = 32, className, signal }: MarkProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${SYS.GRID} ${SYS.GRID}`}
      fill="none"
      aria-hidden="true"
      className={className}
    >
      <path d={SOMMERSETH.horizon} stroke="currentColor" strokeWidth={SYS.STROKE} strokeLinecap="round" />
      <path d={SOMMERSETH.sun} fill={signal ?? 'var(--signal, #C97E1E)'} />
      <path
        d={SOMMERSETH.roof}
        stroke="currentColor"
        strokeWidth={SYS.STROKE}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  )
}

export function AlfaMark({ size = 32, className, signal }: MarkProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${SYS.GRID} ${SYS.GRID}`}
      fill="none"
      aria-hidden="true"
      className={className}
    >
      <path d={ALFA.horizon} stroke="currentColor" strokeWidth={SYS.STROKE} strokeLinecap="round" />
      <path
        d={ALFA.roof}
        stroke="currentColor"
        strokeWidth={SYS.STROKE}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
      <path d={ALFA.door} fill={signal ?? 'var(--signal, #A4762F)'} />
    </svg>
  )
}
