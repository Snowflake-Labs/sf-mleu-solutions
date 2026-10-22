import { useQuery } from '@tanstack/react-query'
import { fetchArchetypeMix, fetchArchetypeRouting, fetchCustomerBack } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])
const one = (d: any) => (Array.isArray(d) ? d[0] : d?._pending ? null : d)

const ARCH_COLOR: Record<string, string> = {
  ENTERPRISE: '#29B5E8', NATIONAL: '#0F766E', LOCAL: '#B45309', INDEPENDENT: '#C62828',
}
const MODE_TONE: Record<string, string> = {
  PROACTIVE: 'bg-emerald-500/15 text-emerald-700 border-emerald-500/30',
  MANAGED_REACTIVE: 'bg-amber-500/15 text-amber-700 border-amber-500/30',
  REACTIVE: 'bg-red-500/15 text-red-700 border-red-500/30',
}

export default function ArchetypePanel({ issueId }: { issueId: string }) {
  const mix = useQuery({ queryKey: ['arch-mix', issueId], queryFn: () => fetchArchetypeMix(issueId), enabled: !!issueId })
  const routing = useQuery({ queryKey: ['arch-route', issueId], queryFn: () => fetchArchetypeRouting(issueId), enabled: !!issueId })
  const cb = useQuery({ queryKey: ['arch-cb', issueId], queryFn: () => fetchCustomerBack(issueId), enabled: !!issueId })

  const rows = arr(mix.data)
  const routeById: Record<string, any> = {}
  arr(routing.data).forEach((r: any) => { routeById[r.ARCHETYPE] = r })
  const c = one(cb.data)
  if (!rows.length) return null

  const totalUnits = rows.reduce((s: number, r: any) => s + Number(r.UNITS || 0), 0)
  const dom = rows.find((r: any) => r.IS_DOMINANT_PAIN) || rows[rows.length - 1]
  const domUnitPct = totalUnits ? Math.round((Number(dom.UNITS) / totalUnits) * 100) : 0

  return (
    <section data-spotlight="issue-archetype" className="animate-fade-in-up">
      <div className="flex items-center gap-3 mb-2">
        <h3 className="text-sm font-semibold tracking-widest text-brand-muted">
          CUSTOMER-BACK · ONE DEFECT, FOUR CUSTOMERS
        </h3>
        <span className="text-[10px] uppercase tracking-widest text-slate-500">
          who feels it · how they define quality · how we reach them
        </span>
      </div>

      {/* customer-back headline */}
      <div className="rounded-lg border border-brand-accent/30 bg-brand-accent/5 p-3 mb-3 text-sm">
        <span className="text-brand-primary font-semibold">{dom.ARCHETYPE[0] + dom.ARCHETYPE.slice(1).toLowerCase()} operators</span>
        <span className="text-brand-text"> are {domUnitPct}% of exposed units but bear </span>
        <span className="text-brand-primary font-bold">{dom.PAIN_SHARE_PCT}%</span>
        <span className="text-brand-text"> of the felt pain. A dollar view chases the biggest accounts; customer-back says reach them first, via {dom.PAIN_CHANNEL?.toLowerCase()}.</span>
        {c && c.ORIG_PRIORITY_RANK != null && (
          <span className="text-brand-muted"> · Standard rank #{c.ORIG_PRIORITY_RANK} · customer-back rank #{c.CUSTOMER_BACK_RANK} in the {c.QUALITY_DIMENSION?.toLowerCase()} tier.</span>
        )}
      </div>

      {/* four archetype rows */}
      <div className="space-y-2">
        {rows.map((r: any) => {
          const rt = routeById[r.ARCHETYPE] || {}
          const color = ARCH_COLOR[r.ARCHETYPE] || '#29B5E8'
          return (
            <div key={r.ARCHETYPE} className="rounded-lg border border-brand-border bg-brand-surface p-3">
              <div className="flex items-center gap-3">
                <div className="w-2 h-8 rounded" style={{ background: color }} />
                <div className="min-w-[150px]">
                  <div className="font-semibold text-sm" style={{ color }}>{r.ARCHETYPE[0] + r.ARCHETYPE.slice(1).toLowerCase()}</div>
                  <div className="text-[10px] text-brand-muted">{r.UNITS} units · {r.CUSTOMERS} customers</div>
                </div>
                <div className="flex-1">
                  <div className="text-xs text-brand-muted mb-1">Quality = <span className="text-brand-text">{r.QUALITY_DEFINITION}</span></div>
                  <div className="h-2 rounded bg-brand-subtle overflow-hidden">
                    <div className="h-full rounded" style={{ width: `${Math.max(2, Number(r.PAIN_SHARE_PCT))}%`, background: color }} />
                  </div>
                  <div className="text-[10px] text-brand-muted mt-0.5">{r.PAIN_SHARE_PCT}% of felt pain</div>
                </div>
                <div className="min-w-[220px] text-right">
                  <div className="text-xs text-brand-text">{rt.OWNER_NAME || r.PAIN_CHANNEL}</div>
                  <span className={`inline-block mt-1 text-[10px] px-2 py-0.5 rounded border ${MODE_TONE[r.RESPONSE_MODE] || 'bg-brand-subtle text-brand-muted border-brand-border'}`}>
                    {(r.RESPONSE_MODE || '').replace('_', ' ')}
                  </span>
                </div>
              </div>
              {rt.RESPONSE_PLAY && (
                <div className="text-xs text-brand-muted mt-2 pl-5 border-l-2" style={{ borderColor: color }}>{rt.RESPONSE_PLAY}</div>
              )}
            </div>
          )
        })}
      </div>
    </section>
  )
}
