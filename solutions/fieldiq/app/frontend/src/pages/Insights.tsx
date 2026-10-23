import { useEffect, useState } from 'react'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
  Line, ScatterChart, Scatter, Cell, AreaChart, Area
} from 'recharts'
import { api } from '../lib/api'
import { ChartCard } from '../components/ChartCard'

const RED = '#E03C31'
const ORANGE = '#F4511E'
const GRAY = '#6B7280'
const DARK = '#1F2937'

const ALERT_COLORS: Record<string, string> = {
  OK: '#16A34A', WATCH: '#F59E0B', WARNING: '#F4511E', CRITICAL: '#E03C31',
}
const STAGE_COLORS: Record<string, string> = {
  Prospecting: '#FCA5A5', Qualification: '#F87171', Proposal: '#EF4444',
  Negotiation: '#E03C31', 'Closed Won': '#16A34A', 'Closed Lost': GRAY,
}

const fmtUsd = (v: number) =>
  v >= 1e6 ? `$${(v/1e6).toFixed(1)}M` : v >= 1e3 ? `$${(v/1e3).toFixed(0)}K` : `$${v?.toFixed?.(0) ?? v}`

export function Insights() {
  const [funnel, setFunnel] = useState<any[]>([])
  const [top, setTop] = useState<any[]>([])
  const [risk, setRisk] = useState<any[]>([])
  const [spend, setSpend] = useState<any[]>([])
  const [ltp, setLtp] = useState<any[]>([])
  const [states, setStates] = useState<any[]>([])
  const [industry, setIndustry] = useState<any[]>([])

  useEffect(() => {
    api.insights.funnel().then(setFunnel).catch(() => {})
    api.insights.topAccounts().then(setTop).catch(() => {})
    api.insights.assetRisk().then(setRisk).catch(() => {})
    api.insights.serviceSpend().then(setSpend).catch(() => {})
    api.insights.leadTimePrice().then(setLtp).catch(() => {})
    api.insights.stateConc().then(setStates).catch(() => {})
    api.insights.industryMix().then(setIndustry).catch(() => {})
  }, [])

  const totalPipeline = funnel.filter(r => !r.STAGE?.startsWith('Closed')).reduce((s, r) => s + (r.TOTAL_AMOUNT_USD || 0), 0)
  const qualPct = funnel.length ? ((funnel.find(r => r.STAGE === 'Qualification')?.TOTAL_AMOUNT_USD || 0) / Math.max(totalPipeline, 1)) * 100 : 0
  const totalAssets = risk.reduce((s, r) => s + (r.ASSETS || 0), 0)
  const criticalCt = risk.find(r => r.ALERT_LEVEL === 'CRITICAL')?.ASSETS || 0
  const warnCt = risk.find(r => r.ALERT_LEVEL === 'WARNING')?.ASSETS || 0
  const noPlanTotal = risk.reduce((s, r) => s + (r.WITHOUT_PLAN || 0), 0)

  return (
    <div className="p-6 space-y-6 bg-canvas-50 min-h-full">
      <div>
        <div className="flex items-baseline gap-3">
          <h1 className="text-2xl font-bold text-apex-dark">Insights</h1>
          <div className="text-sm text-canvas-500">A field-sales view of pipeline, assets, and engineering economics</div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        <ChartCard
          title="Two-thirds of pipeline is stuck in early stages"
          insight={`${fmtUsd(totalPipeline)} of open pipeline; ~${qualPct.toFixed(0)}% sits in Qualification, suggesting reps need help advancing prospects.`}
          source="V_PIPELINE_BY_STAGE">
          <ResponsiveContainer width="100%" height={250}>
            <BarChart data={funnel} margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
              <CartesianGrid strokeDasharray="2 4" stroke="#E5E7EB" vertical={false} />
              <XAxis dataKey="STAGE" tick={{ fontSize: 11, fill: GRAY }} interval={0} angle={-15} dy={10} height={50}/>
              <YAxis tickFormatter={fmtUsd} tick={{ fontSize: 11, fill: GRAY }} />
              <Tooltip formatter={(v: number) => fmtUsd(v)} labelStyle={{ color: DARK }}/>
              <Bar dataKey="TOTAL_AMOUNT_USD" radius={[3, 3, 0, 0]}>
                {funnel.map((r, i) => <Cell key={i} fill={STAGE_COLORS[r.STAGE] || RED}/>)}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        <ChartCard
          title={`${noPlanTotal} of ${totalAssets} installed units lack an ApexCare plan`}
          insight={`${criticalCt} CRITICAL and ${warnCt} WARNING alerts are running in the field — a service-attach upsell opportunity.`}
          source="ATOMIC.ASSETS">
          <ResponsiveContainer width="100%" height={250}>
            <BarChart data={risk} layout="vertical" margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
              <CartesianGrid strokeDasharray="2 4" stroke="#E5E7EB" horizontal={false} />
              <XAxis type="number" tick={{ fontSize: 11, fill: GRAY }} />
              <YAxis dataKey="ALERT_LEVEL" type="category" width={80} tick={{ fontSize: 11, fill: GRAY }}/>
              <Tooltip />
              <Bar dataKey="ASSETS" name="Total assets" radius={[0, 3, 3, 0]}>
                {risk.map((r, i) => <Cell key={i} fill={ALERT_COLORS[r.ALERT_LEVEL] || GRAY}/>)}
              </Bar>
              <Bar dataKey="WITHOUT_PLAN" name="No service plan" radius={[0, 3, 3, 0]} fill={DARK} />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        <ChartCard
          title="Service spend is concentrated in heavier asset months"
          insight="Total Apex service revenue (parts + labour) over the last 18 months. Peaks reveal seasonal shutdown windows worth proactively staffing."
          source="ATOMIC.SERVICE_ACTIVITIES">
          <ResponsiveContainer width="100%" height={250}>
            <AreaChart data={spend} margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
              <defs>
                <linearGradient id="g1" x1="0" x2="0" y1="0" y2="1">
                  <stop offset="0%" stopColor={RED} stopOpacity={0.55}/>
                  <stop offset="100%" stopColor={RED} stopOpacity={0.05}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="2 4" stroke="#E5E7EB" vertical={false}/>
              <XAxis dataKey="MONTH" tick={{ fontSize: 10, fill: GRAY }} />
              <YAxis tickFormatter={fmtUsd} tick={{ fontSize: 11, fill: GRAY }} />
              <Tooltip formatter={(v: number) => fmtUsd(v)}/>
              <Area type="monotone" dataKey="SERVICE_SPEND" stroke={RED} strokeWidth={2} fill="url(#g1)"/>
            </AreaChart>
          </ResponsiveContainer>
        </ChartCard>

        <ChartCard
          title="Lead time grows non-linearly with horsepower"
          insight="Each dot is a SKU. Larger compressors cost more and ship slower — useful when negotiating delivery dates against price."
          source="ATOMIC.PRODUCTS">
          <ResponsiveContainer width="100%" height={250}>
            <ScatterChart margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
              <CartesianGrid strokeDasharray="2 4" stroke="#E5E7EB"/>
              <XAxis type="number" dataKey="HP" name="HP" tick={{ fontSize: 11, fill: GRAY }} label={{ value: 'Horsepower', position: 'insideBottom', dy: 10, fontSize: 11, fill: GRAY }}/>
              <YAxis type="number" dataKey="LEAD_WEEKS" name="Lead time" tick={{ fontSize: 11, fill: GRAY }} label={{ value: 'Lead (weeks)', angle: -90, position: 'insideLeft', fontSize: 11, fill: GRAY }}/>
              <Tooltip cursor={{ strokeDasharray: '3 3' }} formatter={(v: number, n: string) => n === 'PRICE' ? fmtUsd(v) : v}/>
              <Scatter data={ltp} fill={RED}>
                {ltp.map((r, i) => {
                  const fam = r.PRODUCT_FAMILY
                  const c = fam?.includes('Centrifugal') ? DARK : fam?.includes('Diesel') ? ORANGE : fam?.includes('Vacuum') ? GRAY : RED
                  return <Cell key={i} fill={c}/>
                })}
              </Scatter>
            </ScatterChart>
          </ResponsiveContainer>
          <div className="mt-2 flex flex-wrap gap-3 text-[10px] text-canvas-500">
            <span><span className="inline-block w-2 h-2 mr-1" style={{background: RED}}/>Rotary Screw</span>
            <span><span className="inline-block w-2 h-2 mr-1" style={{background: DARK}}/>Centrifugal</span>
            <span><span className="inline-block w-2 h-2 mr-1" style={{background: ORANGE}}/>Diesel Recip</span>
            <span><span className="inline-block w-2 h-2 mr-1" style={{background: GRAY}}/>Vacuum / Other</span>
          </div>
        </ChartCard>

        <ChartCard
          title="Top 10 accounts hold the bulk of open pipeline"
          insight="A short list of accounts dominates the funnel. Concentrate field-sales attention here for highest near-term yield."
          source="V_ACCOUNT_360">
          <ResponsiveContainer width="100%" height={290}>
            <BarChart data={top} layout="vertical" margin={{ top: 10, right: 16, left: 30, bottom: 4 }}>
              <CartesianGrid strokeDasharray="2 4" stroke="#E5E7EB" horizontal={false}/>
              <XAxis type="number" tickFormatter={fmtUsd} tick={{ fontSize: 11, fill: GRAY }}/>
              <YAxis dataKey="ACCOUNT_NAME" type="category" width={140} tick={{ fontSize: 11, fill: GRAY }}/>
              <Tooltip formatter={(v: number) => fmtUsd(v)}/>
              <Bar dataKey="OPEN_PIPELINE_USD" fill={RED} radius={[0, 3, 3, 0]}/>
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        <ChartCard
          title="Pipeline geography skews toward five US states"
          insight="A handful of states drive most of the open pipeline; consider regional rep coverage and partner-channel investment accordingly."
          source="V_ACCOUNT_360 (BILLING_STATE)">
          <ResponsiveContainer width="100%" height={290}>
            <BarChart data={states.slice(0, 12)} margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
              <CartesianGrid strokeDasharray="2 4" stroke="#E5E7EB" vertical={false}/>
              <XAxis dataKey="STATE" tick={{ fontSize: 11, fill: GRAY }}/>
              <YAxis yAxisId="l" tickFormatter={fmtUsd} tick={{ fontSize: 11, fill: GRAY }}/>
              <YAxis yAxisId="r" orientation="right" tick={{ fontSize: 11, fill: GRAY }}/>
              <Tooltip formatter={(v: number, n: string) => n === 'PIPELINE' ? fmtUsd(v) : v}/>
              <Bar yAxisId="l" dataKey="PIPELINE" fill={RED} radius={[3, 3, 0, 0]}/>
              <Line yAxisId="r" type="monotone" dataKey="ACCOUNTS" stroke={DARK} strokeWidth={2} dot={{ r: 3 }}/>
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        <ChartCard
          title="Industry mix: Chemicals & Food/Bev anchor the install base"
          insight="Pipeline value by industry — a window into where Apex should evolve verticalised reference architectures and case studies."
          source="V_ACCOUNT_360 (INDUSTRY)" className="lg:col-span-2">
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={industry} margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
              <CartesianGrid strokeDasharray="2 4" stroke="#E5E7EB" vertical={false}/>
              <XAxis dataKey="INDUSTRY" tick={{ fontSize: 11, fill: GRAY }} interval={0} angle={-12} dy={10} height={50}/>
              <YAxis tickFormatter={fmtUsd} tick={{ fontSize: 11, fill: GRAY }}/>
              <Tooltip formatter={(v: number, n: string) => n === 'PIPELINE' ? fmtUsd(v) : v}/>
              <Bar dataKey="PIPELINE" fill={RED} radius={[3, 3, 0, 0]}/>
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>
      </div>
    </div>
  )
}
