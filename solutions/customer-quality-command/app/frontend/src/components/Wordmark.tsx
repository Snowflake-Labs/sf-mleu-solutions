import { BRAND, THEME } from '../config/brand'

// Neutral product wordmark generated from config/brand.ts (no image assets).
export function BrandMark({ size = 28, inverted = false }: { size?: number; inverted?: boolean }) {
  const fill = inverted ? '#FFFFFF' : THEME.primary
  const accent = THEME.accent
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden="true">
      <rect x="2" y="2" width="28" height="28" rx="8" fill={fill} />
      <path d="M9 17.5l4.5 4.5L23 11" fill="none" stroke={inverted ? THEME.primary : '#FFFFFF'} strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="24.5" cy="7.5" r="3.5" fill={accent} />
    </svg>
  )
}

export default function Wordmark({ inverted = false, showName = true }: { inverted?: boolean; showName?: boolean }) {
  return (
    <div className="flex items-center gap-2.5">
      <BrandMark inverted={inverted} />
      <div className="leading-tight">
        <div className={`font-bold tracking-tight text-lg ${inverted ? 'text-white' : 'text-brand-primary'}`}>{BRAND.productShort}</div>
        {showName && (
          <div className={`text-[10px] uppercase tracking-widest ${inverted ? 'text-white/70' : 'text-brand-muted'}`}>
            {BRAND.productName}
          </div>
        )}
      </div>
    </div>
  )
}
