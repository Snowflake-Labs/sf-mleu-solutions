import { useEffect, useState } from 'react'
import { NavCtx } from '../App'
import { api } from '../lib/api'
import { Chat } from '../components/Chat'

type Mode = 'docs' | 'products'

export function Knowledge(ctx: NavCtx) {
  const [mode, setMode] = useState<Mode>('docs')
  const [q, setQ] = useState('')
  const [docs, setDocs] = useState<any[]>([])
  const [prods, setProds] = useState<any[]>([])

  useEffect(() => { api.docs({ limit: 50 }).then(d => setDocs(d.docs)); api.products({ limit: 50 }).then(d => setProds(d.products)) }, [])
  useEffect(() => {
    const t = setTimeout(() => {
      if (mode === 'docs') api.docs({ q, limit: 50 }).then(d => setDocs(d.docs))
      else api.products({ q, limit: 50 }).then(d => setProds(d.products))
    }, 200)
    return () => clearTimeout(t)
  }, [q, mode])

  return (
    <div className="grid grid-cols-12 gap-6 p-6 h-full">
      <div className="col-span-12 xl:col-span-8 space-y-4 min-w-0">
        <div className="apex-card p-5">
          <div className="flex items-center justify-between mb-4">
            <div className="flex gap-2">
              {(['docs','products'] as Mode[]).map(m => (
                <button key={m} onClick={() => setMode(m)}
                        className={`px-4 py-1.5 text-sm rounded ${mode === m ? 'bg-apex-red text-white' : 'bg-canvas-100 text-apex-dark border border-canvas-300'}`}>
                  {m === 'docs' ? 'Engineering Docs' : 'Product Catalog'}
                </button>
              ))}
            </div>
            <input value={q} onChange={e=>setQ(e.target.value)}
                   placeholder={mode === 'docs' ? 'Search datasheets, drawings, playbooks…' : 'Search products by ID, model, description…'}
                   className="px-3 py-1.5 border border-canvas-300 rounded text-sm focus:border-apex-red focus:outline-none w-80"/>
          </div>

          {mode === 'docs' && (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-xs uppercase tracking-wider text-apex-gray">
                  <tr className="border-b border-canvas-300">
                    <th className="text-left py-2 px-2">Title</th>
                    <th className="text-left py-2 px-2">Type</th>
                    <th className="text-left py-2 px-2">Family</th>
                    <th className="text-left py-2 px-2">Product</th>
                    <th className="text-left py-2 px-2">Format</th>
                  </tr>
                </thead>
                <tbody>
                  {docs.map(d => (
                    <tr key={d.DOC_ID} className="border-b border-canvas-100 hover:bg-canvas-100 cursor-pointer"
                        onClick={() => { ctx.setPrefillPrompt(`Show me ${d.DOC_TITLE}`); ctx.onNavigate('dashboard') }}>
                      <td className="py-2 px-2 font-medium">{d.DOC_TITLE}</td>
                      <td className="py-2 px-2"><span className="text-xs px-2 py-0.5 rounded bg-apex-100 text-apex-red">{d.DOC_TYPE}</span></td>
                      <td className="py-2 px-2">{d.PRODUCT_FAMILY || '—'}</td>
                      <td className="py-2 px-2 font-mono text-xs">{d.PRODUCT_ID || '—'}</td>
                      <td className="py-2 px-2 text-xs">{d.FILE_FORMAT}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {mode === 'products' && (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-xs uppercase tracking-wider text-apex-gray">
                  <tr className="border-b border-canvas-300">
                    <th className="text-left py-2 px-2">Product ID</th>
                    <th className="text-left py-2 px-2">Family / Line</th>
                    <th className="text-left py-2 px-2">HP/kW</th>
                    <th className="text-left py-2 px-2">CFM / PSI</th>
                    <th className="text-right py-2 px-2">Price</th>
                    <th className="text-right py-2 px-2">Lead</th>
                    <th className="text-left py-2 px-2">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {prods.map(p => (
                    <tr key={p.PRODUCT_ID} className="border-b border-canvas-100 hover:bg-canvas-100 cursor-pointer"
                        onClick={() => { ctx.setPrefillPrompt(`Tell me about ${p.PRODUCT_ID} — price, lead time, datasheet`); ctx.onNavigate('dashboard') }}>
                      <td className="py-2 px-2 font-mono">{p.PRODUCT_ID}</td>
                      <td className="py-2 px-2">{p.PRODUCT_FAMILY} <span className="text-apex-gray text-xs">· {p.PRODUCT_LINE}</span></td>
                      <td className="py-2 px-2">{p.HORSEPOWER ? `${p.HORSEPOWER}HP` : ''}{p.KW ? ` / ${p.KW}kW` : ''}</td>
                      <td className="py-2 px-2">{p.CAPACITY_CFM ? `${p.CAPACITY_CFM} CFM` : '—'}{p.PRESSURE_PSI ? ` @ ${p.PRESSURE_PSI} PSI` : ''}</td>
                      <td className="py-2 px-2 text-right">{p.LIST_PRICE_USD ? `$${Number(p.LIST_PRICE_USD).toLocaleString()}` : '—'}</td>
                      <td className="py-2 px-2 text-right">{p.LEAD_TIME_WEEKS}w</td>
                      <td className="py-2 px-2"><span className={`text-xs px-2 py-0.5 rounded ${p.STATUS === 'Active' ? 'bg-green-50 text-green-700' : 'bg-canvas-200 text-apex-gray'}`}>{p.STATUS}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      <div className="col-span-12 xl:col-span-4 min-w-0 min-h-[700px] xl:min-h-0">
        <div className="apex-card h-full flex flex-col">
          <div className="border-b border-canvas-300 px-4 py-3 flex items-center gap-3">
            <div className="apex-corner w-8 h-6"/>
            <div>
              <div className="text-sm font-semibold text-apex-dark">Doc & Catalog Assistant</div>
              <div className="text-[11px] text-apex-gray">Try “Drawing for C750 GA” or “How to sell 10HP diesel recip”</div>
            </div>
          </div>
          <Chat initialPrompt={ctx.prefillPrompt}
                onConsumed={() => ctx.setPrefillPrompt(null)}
                className="flex-1 min-h-0"/>
        </div>
      </div>
    </div>
  )
}
