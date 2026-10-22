import { useState } from 'react'
import { ChevronDown, PlayCircle } from 'lucide-react'
import type { Persona } from '../types'
import { useDemo } from '../demo/DemoContext'
import { ANCHOR } from '../config/brand'

const PERSONAS: { id: Persona; label: string }[] = [
  { id: 'executive', label: 'Executive' },
  { id: 'dealer', label: 'Dealer' },
  { id: 'product', label: 'Product' },
  { id: 'manufacturing', label: 'Manufacturing' },
  { id: 'supply_chain', label: 'Supply Chain' },
]

export default function PageHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  const [persona, setPersona] = useState<Persona>('executive')
  const [open, setOpen] = useState(false)
  const demo = useDemo()

  return (
    <header className="flex items-center justify-between px-8 py-5 border-b border-brand-border bg-white/90 backdrop-blur sticky top-0 z-10">
      <div>
        <h1 className="text-xl font-bold tracking-tight text-brand-primary">
          {title}
        </h1>
        {subtitle && <p className="text-sm text-brand-muted mt-0.5">{subtitle}</p>}
      </div>

      <div className="flex items-center gap-4">
        {!demo.active && (
          <button
            onClick={() => demo.start()}
            className="flex items-center gap-2 px-4 py-2 rounded bg-brand-accent/10 border border-brand-accent/40 text-brand-primary text-sm font-semibold hover:bg-brand-accent/20 transition-colors"
            title={`Play the guided ${ANCHOR.model} story`}
          >
            <PlayCircle size={15} />
            Story
          </button>
        )}
        <div className="relative">
          <button
            onClick={() => setOpen(o => !o)}
            className="flex items-center gap-2 px-4 py-2 rounded bg-brand-surface border border-brand-border text-sm hover:border-brand-accent"
          >
            Persona: <span className="text-brand-primary font-semibold">
              {PERSONAS.find(p => p.id === persona)?.label}
            </span>
            <ChevronDown size={14} />
          </button>
          {open && (
            <div className="absolute right-0 mt-1 w-48 rounded bg-brand-surface border border-brand-border shadow-xl z-20">
              {PERSONAS.map(p => (
                <button
                  key={p.id}
                  onClick={() => { setPersona(p.id); setOpen(false) }}
                  className={`block w-full text-left px-4 py-2 text-sm hover:bg-brand-subtle ${
                    p.id === persona ? 'text-brand-primary' : 'text-brand-text'
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Fixed anchor machine (from config/brand.ts) */}
        <div className="flex items-center gap-3 pl-4 border-l border-brand-border">
          <div className="text-right leading-tight hidden sm:block">
            <div className="text-[10px] uppercase tracking-widest text-brand-muted">Anchor Unit</div>
            <div className="text-sm font-semibold text-brand-primary">{ANCHOR.model}</div>
          </div>
          <div
            className="h-11 w-16 rounded border border-brand-border bg-gradient-to-br from-brand-navy to-brand-primary text-white flex items-center justify-center text-[11px] font-bold tracking-tight"
            aria-label={`${ANCHOR.model} ${ANCHOR.family}`}
          >
            {ANCHOR.model}
          </div>
        </div>
      </div>
    </header>
  )
}
