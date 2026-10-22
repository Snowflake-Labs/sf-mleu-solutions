import { useQuery } from '@tanstack/react-query'
import { fetchArchetypeMix } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])
const ARCH_COLOR: Record<string, string> = {
  ENTERPRISE: '#29B5E8', NATIONAL: '#0F766E', LOCAL: '#B45309', INDEPENDENT: '#C62828',
}
const cap = (s: string) => s ? s[0] + s.slice(1).toLowerCase() : s

export default function ArchetypeAxisStrip({ issueId }: { issueId: string }) {
  const mix = useQuery({ queryKey: ['arch-mix', issueId], queryFn: () => fetchArchetypeMix(issueId), enabled: !!issueId })
  const rows = arr(mix.data)
  if (!rows.length) return null

  return (
    <div className="rounded-lg border border-brand-border bg-brand-surface p-3">
      <div className="flex items-center gap-3 mb-2">
        <h2 className="text-sm font-semibold tracking-widest text-brand-muted">TWO AXES · ONE FOUNDATION</h2>
        <span className="text-[10px] uppercase tracking-widest text-slate-500">
          who feels it (customer archetype) &nbsp;×&nbsp; who acts (persona, below)
        </span>
      </div>
      <div className="grid grid-cols-4 gap-2">
        {rows.map((r: any) => (
          <div key={r.ARCHETYPE} className="rounded border border-brand-border bg-brand-subtle p-2"
            style={{ borderLeft: `3px solid ${ARCH_COLOR[r.ARCHETYPE] || '#5B6B7A'}` }}>
            <div className="text-xs font-semibold" style={{ color: ARCH_COLOR[r.ARCHETYPE] }}>{cap(r.ARCHETYPE)}</div>
            <div className="text-[10px] text-brand-muted">{r.UNITS} units · {r.PAIN_SHARE_PCT}% of felt pain</div>
            <div className="text-[10px] text-brand-muted mt-0.5">{r.PAIN_CHANNEL}</div>
          </div>
        ))}
      </div>
    </div>
  )
}
