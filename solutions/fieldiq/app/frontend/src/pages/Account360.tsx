import { useEffect, useState } from 'react'
import { NavCtx } from '../App'
import { api } from '../lib/api'
import { ChatPanel } from '../components/ChatPanel'

type Tab = 'overview' | 'contacts' | 'orders' | 'opps' | 'assets' | 'services'

export function Account360(ctx: NavCtx) {
  const id = ctx.selectedAccountId
  const [account, setAccount] = useState<any>(null)
  const [tab, setTab] = useState<Tab>('overview')
  const [tabData, setTabData] = useState<any[]>([])
  const [accounts, setAccounts] = useState<any[]>([])
  const [q, setQ] = useState('')

  useEffect(() => { api.accounts({ limit: 50 }).then(d => setAccounts(d.accounts)) }, [])
  useEffect(() => {
    const t = setTimeout(() => api.accounts({ q, limit: 50 }).then(d => setAccounts(d.accounts)), 250)
    return () => clearTimeout(t)
  }, [q])

  useEffect(() => {
    if (!id) return
    api.account(id).then(d => setAccount(d.account))
    setTab('overview'); setTabData([])
  }, [id])

  useEffect(() => {
    if (!id) return
    if (tab === 'contacts') api.contacts(id).then(d => setTabData(d.contacts))
    if (tab === 'orders')   api.orders(id).then(d => setTabData(d.orders))
    if (tab === 'opps')     api.opportunities(id).then(d => setTabData(d.opportunities))
    if (tab === 'assets')   api.assets(id).then(d => setTabData(d.assets))
    if (tab === 'services') api.services(id).then(d => setTabData(d.services))
  }, [id, tab])

  if (!id) {
    return (
      <div className="p-6 h-full">
        <div className="max-w-xl apex-card p-5">
          <div className="text-sm font-semibold mb-3">Pick an account</div>
          <input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search..."
                 className="w-full mb-3 px-3 py-1.5 border border-canvas-300 rounded text-sm focus:border-apex-red focus:outline-none"/>
          <div className="space-y-1 max-h-[600px] overflow-y-auto">
            {accounts.map(a => (
              <button key={a.ACCOUNT_ID} onClick={() => ctx.setSelectedAccountId(a.ACCOUNT_ID)}
                      className="w-full text-left px-3 py-2 rounded hover:bg-canvas-100 text-sm flex justify-between">
                <span className="font-medium">{a.ACCOUNT_NAME}</span>
                <span className="text-xs text-apex-gray">{a.INDUSTRY}</span>
              </button>
            ))}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="p-6 space-y-4 h-full overflow-y-auto">
      <div className="apex-card p-5">
        <div className="flex items-start justify-between">
          <div>
            <div className="text-xs text-apex-gray uppercase tracking-wider">Account</div>
            <div className="text-2xl font-bold text-apex-dark mt-1">{account?.ACCOUNT_NAME ?? '...'}</div>
            <div className="text-sm text-apex-gray mt-1">
              {account?.INDUSTRY} &middot; {account?.BILLING_CITY}, {account?.BILLING_STATE} &middot;
              Tier <span className="font-medium">{account?.ACCOUNT_TIER}</span> &middot;
              Owner <span className="font-medium">{account?.ACCOUNT_OWNER}</span>
            </div>
          </div>
          <button onClick={() => ctx.setSelectedAccountId(null)} className="apex-btn-secondary text-xs">Change account</button>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mt-4">
          <Mini label="Pipeline" value={fmtUSD(account?.OPEN_PIPELINE_USD)}/>
          <Mini label="Open Orders" value={fmtUSD(account?.OPEN_ORDER_VALUE_USD)}/>
          <Mini label="Assets" value={account?.INSTALLED_ASSET_COUNT}/>
          <Mini label="At Risk" value={account?.ASSETS_AT_RISK} red={(account?.ASSETS_AT_RISK ?? 0) > 0}/>
          <Mini label="Service Plan" value={account?.SERVICE_PLAN}/>
        </div>
      </div>

      <div className="apex-card">
        <div className="flex border-b border-canvas-300 overflow-x-auto">
          {(['overview','contacts','orders','opps','assets','services'] as Tab[]).map(t => (
            <button key={t} onClick={() => setTab(t)}
                    className={`px-4 py-2.5 text-sm font-medium whitespace-nowrap ${tab === t ? 'border-b-2 border-apex-red text-apex-red' : 'text-apex-gray hover:text-apex-dark'}`}>
              {tabLabel(t)}
            </button>
          ))}
        </div>
        <div className="p-4">
          {tab === 'overview' && (
            <div className="text-sm text-apex-gray space-y-2">
              <div>Annual Revenue: <span className="font-semibold text-apex-dark">${(account?.ANNUAL_REVENUE_M ?? 0).toFixed(1)}M</span></div>
              <div>Employees: {account?.EMPLOYEES?.toLocaleString()}</div>
              <div>Last Activity: {account?.LAST_ACTIVITY_DATE ?? '---'}</div>
              <div>Service Spend (LTM): {fmtUSD(account?.SERVICE_SPEND_LTM_USD)}</div>
            </div>
          )}
          {tab !== 'overview' && <AccDataTable rows={tabData} kind={tab} />}
        </div>
      </div>

      <ChatPanel initialPrompt={ctx.prefillPrompt} onConsumed={() => ctx.setPrefillPrompt(null)} />
    </div>
  )
}

function tabLabel(t: Tab) {
  return ({overview:'Overview',contacts:'Contacts',orders:'Open Orders',opps:'Opportunities',assets:'Assets',services:'Service Activities'} as any)[t]
}

function Mini({label,value,red}:{label:string;value:any;red?:boolean}) {
  return (
    <div>
      <div className="text-[11px] text-apex-gray uppercase tracking-wider">{label}</div>
      <div className={`text-lg font-semibold ${red ? 'text-apex-red':'text-apex-dark'} mt-0.5`}>{value ?? '---'}</div>
    </div>
  )
}

function AccDataTable({ rows, kind }: { rows: any[]; kind: string }) {
  if (!rows || rows.length === 0) return <div className="text-sm text-apex-gray italic">No records</div>
  const cols = pickCols(kind, rows[0])
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="text-xs uppercase tracking-wider text-apex-gray">
          <tr className="border-b border-canvas-300">
            {cols.map(c => <th key={c} className="text-left py-2 px-2">{c.replace(/_/g,' ')}</th>)}
          </tr>
        </thead>
        <tbody>
          {rows.map((r,i) => (
            <tr key={i} className="border-b border-canvas-100 hover:bg-canvas-100">
              {cols.map(c => <td key={c} className="py-2 px-2">{format(r[c])}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function pickCols(kind: string, sample: any) {
  const presets: Record<string,string[]> = {
    contacts: ['FIRST_NAME','LAST_NAME','TITLE','DEPARTMENT','EMAIL','PHONE','DECISION_ROLE'],
    orders:   ['ORDER_ID','PRODUCT_ID','MODEL_CODE','ORDER_STATUS','QUANTITY','LINE_TOTAL_USD','PROMISED_SHIP_DATE'],
    opps:     ['OPP_NAME','STAGE','PRODUCT_ID','AMOUNT_USD','PROBABILITY_PCT','CLOSE_DATE','OWNER'],
    assets:   ['SERIAL_NUMBER','MODEL_CODE','PRODUCT_FAMILY','SERVICE_PLAN','OPERATING_HOURS','HEALTH_SCORE','ALERT_LEVEL','NEXT_PM_DATE'],
    services: ['ACTIVITY_DATE','ACTIVITY_TYPE','TECHNICIAN','MODEL_CODE','DESCRIPTION','TOTAL_COST_USD','STATUS'],
  }
  return presets[kind] || Object.keys(sample).slice(0, 8)
}

function format(v: any) {
  if (v == null) return '---'
  if (typeof v === 'number') {
    if (Math.abs(v) >= 1000) return v.toLocaleString()
    return String(v)
  }
  return String(v)
}

function fmtUSD(v: any) {
  if (v == null) return '---'
  const n = Number(v)
  if (n >= 1e6) return '$' + (n / 1e6).toFixed(1) + 'M'
  if (n >= 1e3) return '$' + (n / 1e3).toFixed(1) + 'K'
  return '$' + n.toFixed(0)
}
