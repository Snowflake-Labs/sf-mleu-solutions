import { useQuery } from '@tanstack/react-query'
import { fetchArchetypeDistribution } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])
const ARCH_COLOR: Record<string, string> = {
  ENTERPRISE: '#29B5E8', NATIONAL: '#0F766E', LOCAL: '#B45309', INDEPENDENT: '#C62828',
}
const cap = (s: string) => s ? s[0] + s.slice(1).toLowerCase() : s

export default function ArchetypeBand() {
  const dist = useQuery({ queryKey: ['arch-dist'], queryFn: fetchArchetypeDistribution })
  const rows = arr(dist.data)
  if (!rows.length) return null
  const total = rows.reduce((s: number, r: any) => s + Number(r.CUSTOMERS || 0), 0)

  return (
    <div data-spotlight="archetype-band">
      <div className="flex items-center gap-3 mb-2">
        <h2 className="text-sm font-semibold tracking-widest text-brand-muted">CUSTOMER ARCHETYPE MIX</h2>
        <span className="text-[10px] uppercase tracking-widest text-slate-500">
          issues scored customer-back · pain weighted by how each tier defines quality
        </span>
      </div>
      <div className="rounded-lg border border-brand-border bg-brand-surface p-3">
        <div className="flex h-3 rounded overflow-hidden mb-3">
          {rows.map((r: any) => (
            <div key={r.ARCHETYPE} title={`${cap(r.ARCHETYPE)} · ${r.CUSTOMERS} (${r.PCT}%)`}
              style={{ width: `${(Number(r.CUSTOMERS) / total) * 100}%`, background: ARCH_COLOR[r.ARCHETYPE] || '#5B6B7A' }} />
          ))}
        </div>
        <div className="grid grid-cols-4 gap-3">
          {rows.map((r: any) => (
            <div key={r.ARCHETYPE} className="flex items-start gap-2">
              <div className="w-2 h-8 rounded mt-0.5" style={{ background: ARCH_COLOR[r.ARCHETYPE] || '#5B6B7A' }} />
              <div>
                <div className="text-sm font-semibold" style={{ color: ARCH_COLOR[r.ARCHETYPE] }}>{cap(r.ARCHETYPE)}</div>
                <div className="text-[10px] text-brand-muted">{r.OPERATIONS_LABEL}</div>
                <div className="text-xs text-brand-text mt-0.5">{Number(r.CUSTOMERS).toLocaleString()} <span className="text-brand-muted">· {r.PCT}%</span></div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
