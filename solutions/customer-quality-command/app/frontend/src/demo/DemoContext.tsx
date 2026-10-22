// Story Mode controller — holds the pointer, drives navigation, warms the next step.
import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { DEMO_STEPS } from './demoScript'

interface DemoState {
  active: boolean
  index: number
  playing: boolean
  step: (typeof DEMO_STEPS)[number] | null
  total: number
  start: () => void
  exit: () => void
  next: () => void
  prev: () => void
  goto: (i: number) => void
  togglePlay: () => void
}

const Ctx = createContext<DemoState | null>(null)
const KEY = 'cqc.story'

interface Persisted { active: boolean; index: number; playing: boolean }

function load(): Persisted {
  try {
    const raw = sessionStorage.getItem(KEY)
    if (raw) return JSON.parse(raw)
  } catch { /* noop */ }
  return { active: false, index: 0, playing: false }
}

export function DemoProvider({ children }: { children: React.ReactNode }) {
  const nav = useNavigate()
  const qc = useQueryClient()
  const init = useRef(load())
  const [active, setActive] = useState(init.current.active)
  const [index, setIndex] = useState(init.current.index)
  const [playing, setPlaying] = useState(init.current.playing)

  const total = DEMO_STEPS.length
  const step = active ? DEMO_STEPS[index] : null

  // persist
  useEffect(() => {
    sessionStorage.setItem(KEY, JSON.stringify({ active, index, playing }))
  }, [active, index, playing])

  // navigate whenever the active step changes
  useEffect(() => {
    if (active && step) nav(step.path)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, index])

  // best-effort warm the NEXT step's reads (warehouse result cache)
  useEffect(() => {
    if (!active) return
    const nxt = DEMO_STEPS[index + 1]
    nxt?.prewarm?.forEach(p => { fetch('/api' + p).catch(() => {}) })
  }, [active, index])

  const goto = useCallback((i: number) => {
    setIndex(Math.max(0, Math.min(DEMO_STEPS.length - 1, i)))
  }, [])

  const next = useCallback(() => {
    setIndex(i => Math.min(DEMO_STEPS.length - 1, i + 1))
  }, [])
  const prev = useCallback(() => {
    setIndex(i => Math.max(0, i - 1))
  }, [])

  const start = useCallback(() => {
    // warm the very first step immediately
    DEMO_STEPS[0]?.prewarm?.forEach(p => { fetch('/api' + p).catch(() => {}) })
    setIndex(0); setActive(true)
  }, [])

  const exit = useCallback(() => {
    setActive(false); setPlaying(false)
    qc.invalidateQueries()
  }, [qc])

  const togglePlay = useCallback(() => setPlaying(p => !p), [])

  // auto-advance timer (only when playing, active, and step is not a live "hold" step)
  useEffect(() => {
    if (!active || !playing || !step || step.hold) return
    if (index >= DEMO_STEPS.length - 1) { setPlaying(false); return }
    const t = setTimeout(() => setIndex(i => i + 1), step.dwellMs ?? 10000)
    return () => clearTimeout(t)
  }, [active, playing, index, step])

  return (
    <Ctx.Provider value={{ active, index, playing, step, total, start, exit, next, prev, goto, togglePlay }}>
      {children}
    </Ctx.Provider>
  )
}

export function useDemo(): DemoState {
  const c = useContext(Ctx)
  if (!c) throw new Error('useDemo must be used within DemoProvider')
  return c
}
