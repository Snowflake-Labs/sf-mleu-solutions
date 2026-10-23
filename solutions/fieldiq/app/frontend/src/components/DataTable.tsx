interface Props { rows: any[]; maxRows?: number }
export function DataTable({ rows, maxRows = 10 }: Props) {
  if (!rows || rows.length === 0) return null
  const cols = Object.keys(rows[0])
  const shown = rows.slice(0, maxRows)
  const fmt = (v: any) => {
    if (v === null || v === undefined) return '—'
    if (typeof v === 'number') return Number.isInteger(v) ? v.toLocaleString() : v.toFixed(2)
    return String(v)
  }
  return (
    <div className="overflow-x-auto rounded border border-canvas-300 bg-white">
      <table className="text-[11px] w-full">
        <thead className="bg-canvas-100 text-apex-gray">
          <tr>{cols.map(c => <th key={c} className="text-left px-2 py-1 font-semibold whitespace-nowrap">{c}</th>)}</tr>
        </thead>
        <tbody>
          {shown.map((r, i) => (
            <tr key={i} className="border-t border-canvas-200">
              {cols.map(c => <td key={c} className="px-2 py-1 whitespace-nowrap">{fmt(r[c])}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
      {rows.length > maxRows && <div className="text-[10px] text-apex-gray px-2 py-1">…{rows.length - maxRows} more rows</div>}
    </div>
  )
}
