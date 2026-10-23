import { useEffect, useMemo, useState } from 'react'
import { MapContainer, TileLayer, CircleMarker, Tooltip, Popup, ZoomControl } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import { api } from '../lib/api'

const RED = '#E03C31'
const ORANGE = '#F4511E'
const AMBER = '#F59E0B'
const GREEN = '#16A34A'
const GRAY = '#6B7280'

function riskColor(critical: number, warn: number, total: number) {
  if (!total) return GRAY
  if (critical > 0) return RED
  if (warn > 0) return ORANGE
  if (warn === 0 && critical === 0) return GREEN
  return AMBER
}

const fmtUsd = (v?: number) =>
  v == null ? '—' :
  v >= 1e6 ? `$${(v/1e6).toFixed(1)}M` :
  v >= 1e3 ? `$${(v/1e3).toFixed(0)}K` : `$${v.toFixed(0)}`

export function CustomerMap() {
  const [accounts, setAccounts] = useState<any[]>([])
  const [tier, setTier] = useState<string>('')
  const [industry, setIndustry] = useState<string>('')

  useEffect(() => {
    api.accounts({ limit: 500 }).then(d => setAccounts(d.accounts || []))
  }, [])

  const filtered = useMemo(() =>
    accounts.filter(a =>
      a.LATITUDE && a.LONGITUDE &&
      (!tier || a.ACCOUNT_TIER === tier) &&
      (!industry || a.INDUSTRY === industry)
    ),
  [accounts, tier, industry])

  const tiers = useMemo(() => Array.from(new Set(accounts.map(a => a.ACCOUNT_TIER).filter(Boolean))), [accounts])
  const inds  = useMemo(() => Array.from(new Set(accounts.map(a => a.INDUSTRY).filter(Boolean))), [accounts])

  const totals = useMemo(() => ({
    accounts: filtered.length,
    pipeline: filtered.reduce((s, a) => s + (a.OPEN_PIPELINE_USD || 0), 0),
    assets: filtered.reduce((s, a) => s + (a.INSTALLED_ASSET_COUNT || 0), 0),
    risk: filtered.reduce((s, a) => s + (a.ASSETS_AT_RISK || 0), 0),
  }), [filtered])

  return (
    <div className="h-full flex flex-col bg-canvas-50">
      <div className="px-6 pt-6 pb-3">
        <div className="flex items-baseline justify-between">
          <div>
            <h1 className="text-2xl font-bold text-apex-dark">Customer Map</h1>
            <div className="text-sm text-canvas-500">Account locations sized by pipeline, coloured by asset health</div>
          </div>
          <div className="flex gap-2 text-sm">
            <select value={tier} onChange={e => setTier(e.target.value)} className="border border-canvas-300 rounded px-2 py-1 bg-white">
              <option value="">All tiers</option>
              {tiers.map(t => <option key={t} value={t}>{t}</option>)}
            </select>
            <select value={industry} onChange={e => setIndustry(e.target.value)} className="border border-canvas-300 rounded px-2 py-1 bg-white">
              <option value="">All industries</option>
              {inds.map(i => <option key={i} value={i}>{i}</option>)}
            </select>
          </div>
        </div>

        <div className="mt-3 grid grid-cols-4 gap-3">
          <KPI label="Accounts on map"     value={totals.accounts.toLocaleString()}/>
          <KPI label="Open pipeline"        value={fmtUsd(totals.pipeline)}/>
          <KPI label="Installed assets"     value={totals.assets.toLocaleString()}/>
          <KPI label="Assets at risk"       value={totals.risk.toLocaleString()}/>
        </div>
      </div>

      <div className="flex-1 relative px-6 pb-6">
        <MapContainer center={[39.5, -97]} zoom={4} className="rounded-lg w-full h-[640px] border border-canvas-300" zoomControl={false}>
          <TileLayer
            attribution='&copy; OpenStreetMap, &copy; CARTO'
            url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
          />
          <ZoomControl position="topright"/>
          {filtered.map(a => {
            const radius = 6 + Math.min(20, Math.sqrt(Math.max(0, a.OPEN_PIPELINE_USD || 0)) / 80)
            const critical = Math.max(0, (a.ASSETS_AT_RISK || 0))
            const noPlan = (a.ASSETS_NO_SERVICE_PLAN || 0)
            const color = riskColor(critical, 0, a.INSTALLED_ASSET_COUNT || 0)
            return (
              <CircleMarker key={a.ACCOUNT_ID}
                center={[a.LATITUDE, a.LONGITUDE]} radius={radius}
                pathOptions={{ color, weight: 1.5, fillColor: color, fillOpacity: 0.55 }}>
                <Tooltip direction="top" offset={[0, -6]} opacity={1}>
                  <div className="text-[12px]">
                    <div className="font-semibold">{a.ACCOUNT_NAME}</div>
                    <div className="text-canvas-500">{a.BILLING_CITY}, {a.BILLING_STATE} · {a.INDUSTRY}</div>
                  </div>
                </Tooltip>
                <Popup>
                  <div className="text-[12px] min-w-[220px]">
                    <div className="font-semibold text-[13px] mb-1">{a.ACCOUNT_NAME}</div>
                    <div className="text-canvas-500 mb-2">{a.BILLING_CITY}, {a.BILLING_STATE} · {a.INDUSTRY} · {a.ACCOUNT_TIER}</div>
                    <table className="w-full text-[11px]">
                      <tbody>
                        <tr><td className="text-canvas-500">Pipeline</td><td className="text-right font-semibold">{fmtUsd(a.OPEN_PIPELINE_USD)}</td></tr>
                        <tr><td className="text-canvas-500">Open orders</td><td className="text-right">{fmtUsd(a.OPEN_ORDER_VALUE_USD)}</td></tr>
                        <tr><td className="text-canvas-500">Installed assets</td><td className="text-right">{a.INSTALLED_ASSET_COUNT || 0}</td></tr>
                        <tr><td className="text-canvas-500">At risk</td><td className="text-right text-apex-red">{critical}</td></tr>
                        <tr><td className="text-canvas-500">No service plan</td><td className="text-right">{noPlan}</td></tr>
                        <tr><td className="text-canvas-500">Owner</td><td className="text-right">{a.ACCOUNT_OWNER}</td></tr>
                      </tbody>
                    </table>
                  </div>
                </Popup>
              </CircleMarker>
            )
          })}
        </MapContainer>

        <div className="absolute bottom-10 left-10 bg-white/95 border border-canvas-300 rounded-lg p-3 shadow-md text-[11px]">
          <div className="font-semibold text-apex-dark mb-1">Legend</div>
          <div className="space-y-1">
            <LegendDot color={RED}    label="Has CRITICAL/at-risk assets"/>
            <LegendDot color={GREEN}  label="All assets healthy"/>
            <LegendDot color={GRAY}   label="No installed assets"/>
            <div className="pt-1 mt-1 border-t border-canvas-200 text-canvas-500">Marker size ∝ √(open pipeline $)</div>
          </div>
        </div>
      </div>
    </div>
  )
}

function KPI({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-white border border-canvas-300 rounded p-3">
      <div className="text-[11px] uppercase tracking-wide text-canvas-500">{label}</div>
      <div className="text-xl font-bold text-apex-dark mt-1">{value}</div>
    </div>
  )
}

function LegendDot({ color, label }: { color: string; label: string }) {
  return <div className="flex items-center gap-2"><span className="inline-block w-3 h-3 rounded-full" style={{background: color}}/>{label}</div>
}
