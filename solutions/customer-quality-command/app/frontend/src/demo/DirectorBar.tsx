// The cinematic chrome for Story Mode: spotlight scrim + Director Bar.
import { useEffect, useState, useCallback } from 'react'
import { ChevronLeft, ChevronRight, Play, Pause, X } from 'lucide-react'
import { useDemo } from './DemoContext'

interface Rect { top: number; left: number; width: number; height: number }

function useSpotlightRect(key: string | undefined, active: boolean): Rect | null {
  const [rect, setRect] = useState<Rect | null>(null)
  useEffect(() => {
    if (!active || !key) { setRect(null); return }
    let raf = 0
    // scroll the spotlight target into view once when the step activates
    let scrolled = false
    const scrollOnce = () => {
      if (scrolled) return
      const el = document.querySelector<HTMLElement>(`[data-spotlight="${key}"]`)
      if (el) {
        const r = el.getBoundingClientRect()
        if (r.top < 0 || r.bottom > window.innerHeight) {
          el.scrollIntoView({ behavior: 'smooth', block: 'center' })
        }
        scrolled = true
      }
    }
    const st = setTimeout(scrollOnce, 260)
    const measure = () => {
      const el = document.querySelector<HTMLElement>(`[data-spotlight="${key}"]`)
      if (el) {
        const r = el.getBoundingClientRect()
        if (r.width > 0 && r.height > 0) {
          setRect({ top: r.top, left: r.left, width: r.width, height: r.height })
        }
      } else {
        setRect(null)
      }
    }
    measure()
    // keep the highlight glued while data loads / layout settles
    const iv = setInterval(measure, 220)
    const onScroll = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(measure) }
    window.addEventListener('scroll', onScroll, true)
    window.addEventListener('resize', onScroll)
    return () => {
      clearInterval(iv)
      clearTimeout(st)
      window.removeEventListener('scroll', onScroll, true)
      window.removeEventListener('resize', onScroll)
      cancelAnimationFrame(raf)
    }
  }, [key, active])
  return rect
}

export default function DirectorBar() {
  const demo = useDemo()
  const { active, step, index, total } = demo
  const rect = useSpotlightRect(step?.spotlight, active)

  const next = useCallback(() => demo.next(), [demo])
  const prev = useCallback(() => demo.prev(), [demo])
  const exit = useCallback(() => demo.exit(), [demo])

  // presenter keyboard controls
  useEffect(() => {
    if (!active) return
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName
      if (tag === 'INPUT' || tag === 'TEXTAREA') return
      if (e.key === 'ArrowRight') next()
      else if (e.key === 'ArrowLeft') prev()
      else if (e.key === 'Escape') exit()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [active, next, prev, exit])

  if (!active || !step) return null

  const pad = 10
  const atStart = index === 0
  const atEnd = index === total - 1

  return (
    <>
      {/* Spotlight scrim — dims everything except the highlighted element */}
      {rect && (
        <div
          className="fixed z-[60] pointer-events-none transition-all duration-500 ease-out rounded-xl"
          style={{
            top: rect.top - pad,
            left: rect.left - pad,
            width: rect.width + pad * 2,
            height: rect.height + pad * 2,
            boxShadow: '0 0 0 9999px rgba(0,53,69,0.45)',
            outline: '2px solid rgba(41,181,232,0.9)',
            outlineOffset: '2px',
          }}
        />
      )}

      {/* Director Bar */}
      <div className="fixed bottom-0 inset-x-0 z-[70] pointer-events-none">
        <div className="mx-auto max-w-[1500px] m-4 pointer-events-auto">
          <div className="rounded-2xl border border-brand-accent/30 bg-white/95 backdrop-blur-md shadow-2xl px-5 py-3.5">
            {/* progress dots */}
            <div className="flex items-center gap-1.5 mb-2.5">
              {Array.from({ length: total }).map((_, i) => (
                <button
                  key={i}
                  onClick={() => demo.goto(i)}
                  className={`h-1.5 rounded-full transition-all ${
                    i === index ? 'w-8 bg-brand-primary' : i < index ? 'w-4 bg-brand-accent/40' : 'w-4 bg-brand-subtle'
                  }`}
                  aria-label={`Go to step ${i + 1}`}
                />
              ))}
            </div>

            <div className="flex items-center gap-4">
              {/* act / chapter */}
              <div className="shrink-0 w-56">
                <div className="flex items-baseline gap-2">
                  <span className="text-[10px] font-bold uppercase tracking-[0.25em] text-brand-primary">{step.act}</span>
                  <span className="text-[10px] uppercase tracking-widest text-slate-500">{index + 1}/{total}</span>
                </div>
                <div className="text-base font-bold text-brand-text leading-tight">{step.chapter}</div>
                <div className="text-[10px] uppercase tracking-wider text-brand-muted mt-0.5">{step.theme}</div>
              </div>

              {/* caption */}
              <p className="flex-1 text-sm text-brand-text leading-relaxed border-l border-brand-border pl-4">
                {step.caption}
              </p>

              {/* controls */}
              <div className="shrink-0 flex items-center gap-1.5">
                <button
                  onClick={prev}
                  disabled={atStart}
                  className="h-9 w-9 grid place-items-center rounded-lg border border-brand-border text-brand-text hover:border-brand-accent hover:text-brand-primary disabled:opacity-30"
                  title="Previous (←)"
                >
                  <ChevronLeft size={17} />
                </button>
                <button
                  onClick={demo.togglePlay}
                  className={`h-9 w-9 grid place-items-center rounded-lg border ${
                    demo.playing ? 'border-brand-accent text-brand-primary' : 'border-brand-border text-brand-text hover:border-brand-accent hover:text-brand-primary'
                  }`}
                  title={demo.playing ? 'Pause auto-play' : 'Auto-play'}
                >
                  {demo.playing ? <Pause size={15} /> : <Play size={15} />}
                </button>
                <button
                  onClick={next}
                  disabled={atEnd}
                  className="h-9 px-3.5 grid place-items-center rounded-lg bg-brand-primary text-white font-semibold text-sm hover:bg-brand-primary-dark disabled:opacity-40 gap-1 flex"
                  title="Next (→)"
                >
                  Next <ChevronRight size={16} />
                </button>
                <button
                  onClick={exit}
                  className="h-9 w-9 grid place-items-center rounded-lg border border-brand-border text-brand-muted hover:border-pillar-safety hover:text-pillar-safety ml-1"
                  title="Exit Story Mode (Esc)"
                >
                  <X size={16} />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}
