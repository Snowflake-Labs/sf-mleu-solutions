import { useQuery } from '@tanstack/react-query'
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, BarChart, Bar, XAxis, YAxis, LabelList } from 'recharts'
import PageHeader from '../components/PageHeader'
import { CHART, tooltipStyle } from '../components/charts/theme'
import { fetchDqChecks, fetchConfidence } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])

export default function DataReadiness() {
  const dq = useQuery({ queryKey: ['dq'], queryFn: fetchDqChecks })
  const conf = useQuery({ queryKey: ['conf'], queryFn: fetchConfidence })
  const checks = arr(dq.data)
  const passed = checks.filter((c: any) => c.STATUS === 'PASS').length
  const confList = arr(conf.data)
  const passData = [{ name: 'Pass', value: passed, color: '#059669' }, { name: 'Fail', value: checks.length - passed, color: '#C62828' }]
  const buckets = [
    { name: '<50%', lo: 0, hi: 0.5 }, { name: '50-70%', lo: 0.5, hi: 0.7 },
    { name: '70-85%', lo: 0.7, hi: 0.85 }, { name: '85-95%', lo: 0.85, hi: 0.95 }, { name: '≥95%', lo: 0.95, hi: 1.01 },
  ]
  const histData = buckets.map(b => ({
    name: b.name,
    n: confList.filter((c: any) => (c.DATA_CONFIDENCE || 0) >= b.lo && (c.DATA_CONFIDENCE || 0) < b.hi).length,
  }))

  return (
    <div className="flex-1">
      <PageHeader title="Data Readiness" subtitle="Pipeline data-quality gates and per-issue confidence" />
      <div className="p-8 space-y-6">
        <div className="grid grid-cols-2 gap-4">
          <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
            <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">DQ GATE PASS RATE</h3>
            <div className="relative">
              <ResponsiveContainer width="100%" height={160}>
                <PieChart>
                  <Pie data={passData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={46} outerRadius={68} paddingAngle={2}>
                    {passData.map((d, i) => <Cell key={i} fill={d.color} stroke={CHART.panel} />)}
                  </Pie>
                  <Tooltip {...tooltipStyle} />
                </PieChart>
              </ResponsiveContainer>
              <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                <div className="text-2xl font-bold text-brand-good">{checks.length ? Math.round((passed / checks.length) * 100) : 0}%</div>
                <div className="text-[10px] uppercase tracking-widest text-brand-muted">{passed}/{checks.length} pass</div>
              </div>
            </div>
          </section>
          <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
            <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">ISSUE CONFIDENCE DISTRIBUTION</h3>
            <ResponsiveContainer width="100%" height={160}>
              <BarChart data={histData} margin={{ top: 12, right: 8, bottom: 0, left: -18 }}>
                <XAxis dataKey="name" tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
                <YAxis allowDecimals={false} tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
                <Tooltip {...tooltipStyle} cursor={{ fill: '#E3EAF0' }} />
                <Bar dataKey="n" radius={[3, 3, 0, 0]} fill={CHART.primary}>
                  <LabelList dataKey="n" position="top" fill={CHART.text} fontSize={10} />
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </section>
        </div>

        <section>
          <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">DATA-QUALITY CHECKS</h3>
          <div className="rounded-lg border border-brand-border overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-brand-surface text-brand-muted text-xs uppercase tracking-wider">
                <tr><th className="text-left px-3 py-2">Check</th><th className="text-left px-3 py-2">Target</th><th className="text-left px-3 py-2">Type</th><th className="text-right px-3 py-2">Fail rate</th><th className="text-right px-3 py-2">Rows</th><th className="text-center px-3 py-2">Status</th></tr>
              </thead>
              <tbody>
                {checks.map((c: any, i: number) => (
                  <tr key={i} className="border-t border-brand-border">
                    <td className="px-3 py-2 text-brand-text">{c.CHECK_NAME}</td>
                    <td className="px-3 py-2 text-brand-muted">{c.TARGET_OBJECT}</td>
                    <td className="px-3 py-2 text-brand-muted">{c.CHECK_TYPE}</td>
                    <td className="px-3 py-2 text-right text-brand-text">{(c.RATE * 100).toFixed(2)}%</td>
                    <td className="px-3 py-2 text-right text-brand-muted">{Number(c.DENOMINATOR).toLocaleString()}</td>
                    <td className="px-3 py-2 text-center">
                      <span className={`text-xs px-2 py-0.5 rounded ${c.STATUS === 'PASS' ? 'bg-brand-good/15 text-brand-good' : 'bg-pillar-safety/20 text-pillar-safety'}`}>{c.STATUS}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section>
          <h3 className="text-sm font-semibold tracking-widest text-brand-muted mb-2">LOWEST-CONFIDENCE ISSUES</h3>
          <div className="space-y-2">
            {confList.slice(0, 12).map((c: any) => (
              <div key={c.ISSUE_ID} className="flex items-center gap-3 rounded-lg border border-brand-border bg-brand-surface p-3 text-sm">
                <span className="flex-1 text-brand-text truncate">{c.TITLE}</span>
                <span className="text-xs text-brand-muted">{c.QUALITY_DIMENSION}</span>
                <div className="w-32 h-2 rounded bg-brand-subtle overflow-hidden">
                  <div className="h-full bg-brand-primary" style={{ width: `${(c.DATA_CONFIDENCE || 0) * 100}%` }} />
                </div>
                <span className="w-16 text-right text-brand-text">{((c.DATA_CONFIDENCE || 0) * 100).toFixed(0)}%</span>
                <span className="w-16 text-right text-xs text-brand-muted">{c.DATA_CONFIDENCE_BAND}</span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  )
}
