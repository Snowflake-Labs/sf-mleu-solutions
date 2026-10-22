import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Cell } from 'recharts'
import PageHeader from '../components/PageHeader'
import { CHART, SEQ, tooltipStyle, fmtNum } from '../components/charts/theme'
import { fetchExplorerTables, fetchExplorerPreview } from '../services/api'

const arr = (d: any) => (Array.isArray(d) ? d : [])
const SCHEMAS = ['RAW', 'STAGING', 'ATOMIC', 'FEATURE_STORE', 'ML', 'ANALYTICS', 'INSIGHTS', 'ACTION', 'DOCS']

function fmtBytes(b: number) {
  if (!b) return '—'
  const u = ['B', 'KB', 'MB', 'GB']
  let i = 0, v = b
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
  return `${v.toFixed(1)} ${u[i]}`
}

export default function DataExplorer() {
  const [schema, setSchema] = useState('INSIGHTS')
  const tables = useQuery({ queryKey: ['tables', schema], queryFn: () => fetchExplorerTables(schema) })
  const rows = arr(tables.data)
  const [sel, setSel] = useState<string | null>(null)
  const table = sel || rows[0]?.TABLE_NAME
  const preview = useQuery({
    queryKey: ['preview', schema, table],
    queryFn: () => fetchExplorerPreview(schema, table),
    enabled: !!table,
  })
  const pRows = arr(preview.data)
  const cols = pRows.length ? Object.keys(pRows[0]) : []
  const rowCountData = rows
    .filter((t: any) => Number(t.ROW_COUNT) > 0)
    .map((t: any) => ({ name: t.TABLE_NAME, n: Number(t.ROW_COUNT) }))
    .sort((a: any, b: any) => b.n - a.n).slice(0, 10)

  return (
    <div className="flex-1">
      <PageHeader title="Data Explorer" subtitle="Read-only medallion catalog — browse tables and preview rows" />
      <div className="p-8 space-y-5">
        <div className="flex flex-wrap gap-2">
          {SCHEMAS.map(s => (
            <button key={s} onClick={() => { setSchema(s); setSel(null) }}
              className={`text-xs px-3 py-1.5 rounded border ${schema === s ? 'border-brand-accent text-brand-primary bg-brand-accent/10' : 'border-brand-border text-brand-muted hover:text-brand-text'}`}>
              {s}
            </button>
          ))}
        </div>

        {rowCountData.length > 0 && (
          <section className="rounded-lg border border-brand-border bg-brand-surface p-4">
            <h3 className="text-xs font-semibold tracking-widest text-brand-muted mb-2">TOP TABLES BY ROW COUNT — {schema}</h3>
            <ResponsiveContainer width="100%" height={Math.max(120, rowCountData.length * 26)}>
              <BarChart data={rowCountData} layout="vertical" margin={{ top: 0, right: 60, bottom: 0, left: 8 }}>
                <XAxis type="number" tickFormatter={fmtNum} tick={{ fill: CHART.textDim, fontSize: 10 }} stroke={CHART.grid} />
                <YAxis type="category" dataKey="name" width={200} tick={{ fill: CHART.text, fontSize: 10 }} stroke={CHART.grid} />
                <Tooltip {...tooltipStyle} formatter={(v: any) => fmtNum(v)} cursor={{ fill: '#E3EAF0' }} />
                <Bar dataKey="n" radius={[0, 3, 3, 0]}>
                  {rowCountData.map((_: any, i: number) => <Cell key={i} fill={SEQ[i % SEQ.length]} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </section>
        )}

        <div className="grid grid-cols-[320px_1fr] gap-4">
          <section className="rounded-lg border border-brand-border overflow-hidden">
            <div className="bg-brand-surface px-3 py-2 text-xs uppercase tracking-widest text-brand-muted">{schema} · {rows.length} objects</div>
            <div className="max-h-[560px] overflow-auto">
              {rows.map((t: any) => (
                <div key={t.TABLE_NAME} onClick={() => setSel(t.TABLE_NAME)}
                  className={`px-3 py-2 text-sm cursor-pointer border-t border-brand-border ${table === t.TABLE_NAME ? 'bg-brand-subtle' : 'hover:bg-brand-subtle'}`}>
                  <div className="flex justify-between">
                    <span className="text-brand-text truncate">{t.TABLE_NAME}</span>
                    <span className="text-xs text-brand-muted">{t.TABLE_TYPE === 'VIEW' ? 'view' : Number(t.ROW_COUNT || 0).toLocaleString()}</span>
                  </div>
                  <div className="text-[10px] text-slate-500">{fmtBytes(Number(t.BYTES))}</div>
                </div>
              ))}
            </div>
          </section>

          <section className="rounded-lg border border-brand-border overflow-hidden">
            <div className="bg-brand-surface px-3 py-2 text-xs uppercase tracking-widest text-brand-muted">
              {schema}.{table} · preview {pRows.length} rows
            </div>
            <div className="overflow-auto max-h-[560px]">
              <table className="text-xs">
                <thead className="bg-brand-surface text-brand-muted sticky top-0">
                  <tr>{cols.map(c => <th key={c} className="text-left px-2 py-1.5 whitespace-nowrap font-semibold">{c}</th>)}</tr>
                </thead>
                <tbody>
                  {pRows.map((r: any, i: number) => (
                    <tr key={i} className="border-t border-brand-border">
                      {cols.map(c => <td key={c} className="px-2 py-1 whitespace-nowrap text-brand-text max-w-[280px] truncate" title={String(r[c] ?? '')}>{String(r[c] ?? '')}</td>)}
                    </tr>
                  ))}
                </tbody>
              </table>
              {!pRows.length && <div className="p-4 text-xs text-slate-500">Select a table to preview rows.</div>}
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}
