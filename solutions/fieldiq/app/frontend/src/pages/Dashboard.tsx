import { useEffect, useState } from 'react'
import { NavCtx } from '../App'
import { api } from '../lib/api'
import { ChatPanel } from '../components/ChatPanel'

export function Dashboard(ctx: NavCtx) {
  const [summary, setSummary] = useState<any>(null)
  const [stages, setStages]   = useState<any[]>([])
  const [accounts, setAccounts] = useState<any[]>([])
  const [q, setQ] = useState('')
  const [activeStage, setActiveStage] = useState<string | null>(null)

  useEffect(() => {
    api.portfolioSummary().then(d => { setSummary(d.summary); setStages(d.pipeline_by_stage) })
    api.accounts({ limit: 50 }).then(d => setAccounts(d.accounts))
  }, [])

  useEffect(() => {
    const params: any = { limit: 50 }
    if (q) params.q = q
    if (activeStage) params.stage = activeStage
    const t = setTimeout(() => api.accounts(params).then(d => setAccounts(d.accounts)), 200)
    return () => clearTimeout(t)
  }, [q, activeStage])

  const totalPipeline = stages.reduce((s, x) => s + (x.TOTAL_AMOUNT_USD || 0), 0)

  return (
    <div className="p-6 space-y-6 h-full overflow-y-auto">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <KPI label="Accounts"          value={summary?.ACCOUNT_COUNT?.toLocaleString() ?? '---'} />
        <KPI label="Open Pipeline"     value={fmtUSD(summary?.PIPELINE_TOTAL)} />
        <KPI label="Open Orders Value" value={fmtUSD(summary?.OPEN_ORDERS_TOTAL)} />
        <KPI label="Installed Assets"  value={summary?.INSTALLED_ASSETS?.toLocaleString() ?? '---'}
             sub={`${summary?.ASSETS_AT_RISK ?? 0} at risk`} />
      </div>

      <div className="apex-card p-5">
        <div className="flex items-center justify-between mb-4">
          <div className="text-sm font-semibold text-apex-dark">Pipeline by Stage</div>
          {activeStage && (
            <button onClick={() => setActiveStage(null)}
                    className="text-xs text-apex-red hover:underline">
              Clear filter
            </button>
          )}
        </div>
        <div className="flex items-end gap-1 h-32">
          {stages.map(s => {
            const pct = totalPipeline > 0 ? (s.TOTAL_AMOUNT_USD / totalPipeline) * 100 : 0
            const isActive = activeStage === s.STAGE
            const isFiltering = activeStage !== null
            return (
              <button
                key={s.STAGE}
                onClick={() => setActiveStage(isActive ? null : s.STAGE)}
                className={`flex-1 flex flex-col items-center justify-end h-full rounded-t-lg transition-all group cursor-pointer
                  ${isActive ? 'ring-2 ring-apex-red ring-offset-1' : ''}
                  ${isFiltering && !isActive ? 'opacity-40' : 'opacity-100'}
                `}
              >
                <div className={`w-full rounded-t-md transition-all group-hover:opacity-90 ${isActive ? 'bg-apex-red' : 'bg-gradient-to-t from-apex-red/70 to-apex-red/30'}`}
                     style={{ height: `${Math.max(pct, 8)}%` }} />
                <div className="w-full border-t border-canvas-200 pt-2 pb-1 text-center">
                  <div className="text-[10px] text-apex-gray uppercase tracking-wide truncate px-1">{s.STAGE}</div>
                  <div className="text-sm font-semibold text-apex-dark">{fmtUSD(s.TOTAL_AMOUNT_USD)}</div>
                  <div className="text-[10px] text-apex-gray">{s.OPP_COUNT} opps</div>
                </div>
              </button>
            )
          })}
        </div>
      </div>

      <div className="apex-card p-5">
        <div className="flex items-center justify-between mb-3">
          <div className="text-sm font-semibold text-apex-dark">
            Accounts
            {activeStage && <span className="ml-2 text-xs font-normal text-apex-red bg-red-50 px-2 py-0.5 rounded-full">{activeStage}</span>}
          </div>
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search accounts..."
                 className="px-3 py-1.5 border border-canvas-300 rounded text-sm focus:border-apex-red focus:outline-none w-64" />
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-xs uppercase tracking-wider text-apex-gray">
              <tr className="border-b border-canvas-300">
                <th className="text-left py-2 px-2">Account</th>
                <th className="text-left py-2 px-2">Industry</th>
                <th className="text-left py-2 px-2">Tier</th>
                <th className="text-left py-2 px-2">Plan</th>
                <th className="text-right py-2 px-2">Pipeline</th>
                <th className="text-right py-2 px-2">Orders</th>
                <th className="text-right py-2 px-2">Assets</th>
              </tr>
            </thead>
            <tbody>
              {accounts.map(a => (
                <tr key={a.ACCOUNT_ID}
                    onClick={() => { ctx.setSelectedAccountId(a.ACCOUNT_ID); ctx.onNavigate('account') }}
                    className="border-b border-canvas-100 hover:bg-canvas-100 cursor-pointer">
                  <td className="py-2 px-2 font-medium">{a.ACCOUNT_NAME}</td>
                  <td className="py-2 px-2">{a.INDUSTRY}</td>
                  <td className="py-2 px-2"><span className="text-xs px-2 py-0.5 rounded bg-canvas-200">{a.ACCOUNT_TIER}</span></td>
                  <td className="py-2 px-2 text-xs">{a.SERVICE_PLAN}</td>
                  <td className="py-2 px-2 text-right">{fmtUSD(a.OPEN_PIPELINE_USD)}</td>
                  <td className="py-2 px-2 text-right">{fmtUSD(a.OPEN_ORDER_VALUE_USD)}</td>
                  <td className="py-2 px-2 text-right">
                    {a.INSTALLED_ASSET_COUNT}
                    {a.ASSETS_AT_RISK > 0 && <span className="ml-1 text-xs text-apex-red">!{a.ASSETS_AT_RISK}</span>}
                  </td>
                </tr>
              ))}
              {accounts.length === 0 && (
                <tr><td colSpan={7} className="py-8 text-center text-apex-gray italic">No accounts found</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      <ChatPanel initialPrompt={ctx.prefillPrompt} onConsumed={() => ctx.setPrefillPrompt(null)} />
    </div>
  )
}

function KPI({ label, value, sub }: { label: string; value: any; sub?: string }) {
  return (
    <div className="apex-card p-4">
      <div className="text-xs text-apex-gray uppercase tracking-wider">{label}</div>
      <div className="text-2xl font-bold text-apex-dark mt-1">{value}</div>
      {sub && <div className="text-xs text-apex-gray mt-1">{sub}</div>}
    </div>
  )
}

function fmtUSD(v: any) {
  if (v == null) return '---'
  const n = Number(v)
  if (n >= 1e6) return '$' + (n / 1e6).toFixed(1) + 'M'
  if (n >= 1e3) return '$' + (n / 1e3).toFixed(1) + 'K'
  return '$' + n.toFixed(0)
}
