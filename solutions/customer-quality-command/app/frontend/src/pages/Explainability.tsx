import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import PageHeader from '../components/PageHeader'
import { fetchCuratedIssues, fetchIssueEvidence } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])
const one = (d: any) => (Array.isArray(d) ? d[0] : d?._pending ? null : d)
const parse = (v: any) => { if (!v) return null; if (typeof v === 'object') return v; try { return JSON.parse(v) } catch { return null } }

const CHAIN: { key: string; label: string; icon: string }[] = [
  { key: 'detector', label: 'Signal Detection', icon: '📈' },
  { key: 'concentration', label: 'Concentration', icon: '🎯' },
  { key: 'reliability', label: 'Reliability Fit', icon: '⚙️' },
  { key: 'exposure', label: 'Exposure (Monte-Carlo)', icon: '💰' },
  { key: 'impact', label: 'Customer Impact', icon: '👤' },
  { key: 'support', label: 'Evidence Support', icon: '📚' },
]

const KEY_LABELS: Record<string, string> = {
  pro_sif_risk: 'SIP risk', sif_rate: 'SIP rate',
  p50_usd: 'likely (USD)', p90_usd: 'plan for (USD)', cvar_usd: 'bad case (USD)',
}

function Node({ icon, label, obj }: { icon: string; label: string; obj: any }) {
  return (
    <div className="rounded-lg border border-brand-border bg-brand-surface p-4">
      <div className="flex items-center gap-2 mb-2"><span>{icon}</span><span className="text-sm font-semibold text-brand-text">{label}</span></div>
      <div className="space-y-1 text-sm">
        {Object.entries(obj).map(([k, v]) => (
          <div key={k} className="flex justify-between gap-4">
            <span className="text-brand-muted">{KEY_LABELS[k] ?? k.replace(/_/g, ' ')}</span>
            <span className="text-brand-text text-right">{typeof v === 'number' ? (Math.abs(v) >= 1000 ? v.toLocaleString(undefined, { maximumFractionDigits: 0 }) : String(v)) : String(v)}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

export default function Explainability() {
  const issues = useQuery({ queryKey: ['curated'], queryFn: () => fetchCuratedIssues(15) })
  const list = arr(issues.data)
  const [sel, setSel] = useState<string | null>(null)
  const id = sel || list[0]?.ISSUE_ID
  const evid = useQuery({ queryKey: ['ievid', id], queryFn: () => fetchIssueEvidence(id), enabled: !!id })
  const e = one(evid.data)
  const ev = parse(e?.EVIDENCE)
  const prov = parse(e?.PROVENANCE)

  return (
    <div className="flex-1 min-w-0">
      <PageHeader title="Explainability" subtitle="Traceable evidence chain from raw signal to grounded insight" />
      <div className="p-8 space-y-5">
        <select value={id || ''} onChange={ev => setSel(ev.target.value)}
          className="bg-brand-surface border border-brand-border rounded px-3 py-2 text-sm w-full max-w-xl">
          {list.map((i: any) => <option key={i.ISSUE_ID} value={i.ISSUE_ID}>#{i.PRIORITY_RANK} · {i.TITLE} ({i.QUALITY_DIMENSION})</option>)}
        </select>

        {e && (
          <>
            <div className="flex items-center gap-3">
              <h2 className="text-lg font-bold">{e.TITLE}</h2>
              <span className="text-xs px-2 py-0.5 rounded bg-brand-subtle text-brand-text">{e.ROOT_CAUSE_TYPE}</span>
              <span className="text-xs px-2 py-0.5 rounded bg-brand-accent/20 text-brand-primary">confidence {e.DATA_CONFIDENCE_BAND} ({((e.DATA_CONFIDENCE || 0) * 100).toFixed(0)}%)</span>
            </div>

            {ev && (
              <section>
                <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">EVIDENCE FLOW</h3>
                <div className="rounded-lg border border-brand-border bg-brand-surface p-4 overflow-x-auto">
                  <div className="flex items-center gap-1 min-w-max">
                    {CHAIN.map((c, i) => {
                      const present = ev[c.key] && typeof ev[c.key] === 'object'
                      return (
                        <div key={c.key} className="flex items-center gap-1">
                          <div className={`flex flex-col items-center justify-center rounded-lg border px-4 py-3 w-32 text-center ${present ? 'border-brand-accent/50 bg-brand-accent/5' : 'border-brand-border bg-brand-subtle opacity-50'}`}>
                            <span className="text-xl">{c.icon}</span>
                            <span className={`text-[11px] mt-1 leading-tight ${present ? 'text-brand-text' : 'text-slate-500'}`}>{c.label}</span>
                          </div>
                          {i < CHAIN.length - 1 && <span className="text-brand-primary/60 text-lg">→</span>}
                        </div>
                      )
                    })}
                    <span className="text-brand-primary/60 text-lg">→</span>
                    <div className="flex flex-col items-center justify-center rounded-lg border border-brand-good/40 bg-brand-good/10 px-4 py-3 w-32 text-center">
                      <span className="text-2xl font-bold text-brand-good">{((e.DATA_CONFIDENCE || 0) * 100).toFixed(0)}%</span>
                      <span className="text-[11px] mt-1 leading-tight text-brand-text">Grounded Confidence</span>
                    </div>
                  </div>
                </div>
              </section>
            )}

            {ev && (
              <div className="grid grid-cols-3 gap-3">
                {CHAIN.filter(c => ev[c.key] && typeof ev[c.key] === 'object').map(c => (
                  <Node key={c.key} icon={c.icon} label={c.label} obj={ev[c.key]} />
                ))}
              </div>
            )}

            {e.RATIONALE_TEXT && (
              <section>
                <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">GROUNDED RATIONALE</h3>
                <div className="rounded-lg border border-brand-border bg-brand-surface p-4 text-sm text-brand-text leading-relaxed">{e.RATIONALE_TEXT}</div>
              </section>
            )}

            {prov && (
              <section>
                <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">PROVENANCE</h3>
                <div className="rounded-lg border border-brand-border bg-brand-surface p-4 text-sm flex flex-wrap gap-x-8 gap-y-2">
                  {prov.built_ts && <div><span className="text-brand-muted">Built </span><span className="text-brand-text">{prov.built_ts}</span></div>}
                  {prov.reliability_fit && <div><span className="text-brand-muted">Reliability fit </span><span className="text-brand-text">{prov.reliability_fit}</span></div>}
                  {arr(prov.models).length > 0 && <div><span className="text-brand-muted">Models </span>{prov.models.map((m: string) => <span key={m} className="ml-1 text-xs px-2 py-0.5 rounded bg-brand-subtle text-brand-text">{m}</span>)}</div>}
                </div>
              </section>
            )}
          </>
        )}
      </div>
    </div>
  )
}
