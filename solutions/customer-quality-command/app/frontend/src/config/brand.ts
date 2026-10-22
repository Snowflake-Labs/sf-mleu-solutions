// Single rebrand point for the frontend: product, company, business unit,
// anchor scenario and theme tokens. Tailwind (tailwind.config.ts), chart theme
// (components/charts/theme.ts) and Story Mode (demo/demoScript.ts) all read
// from here. Backend equivalents live in app/backend/config.py.

export const BRAND = {
  productName: 'Customer Quality Command',
  productShort: 'CQC',
  companyName: 'Acme Industrial',
  businessUnit: 'Construction Equipment Division',
  businessUnitShort: 'CED',
  tagline: 'Customer-back quality, from first signal to closed loop',
} as const

// Anchor scenario used by Story Mode and page subtitles. Must match the
// generator's ANCHOR_MODEL (platform/generators/generate_raw.py).
export const ANCHOR = {
  model: 'LX-950',
  family: 'Large Excavator',
  systemGroup: 'ENGINE_FUEL',
  plant: 'South Plant, GA',
  badLot: 'L-4480',
} as const

export const ANCHOR_MACHINE = `${ANCHOR.model} ${ANCHOR.family}`

// Snowflake brand palette (snowflake.com/brand-guidelines) adapted for a light UI.
export const THEME = {
  primary: '#11567F',      // Mid Blue — buttons, active nav, text accents
  primaryDark: '#0C3F5E',
  accent: '#29B5E8',       // Snowflake Blue — fills, borders, focus, charts
  navy: '#003545',         // Iceberg — sidebar
  bg: '#F5F8FB',
  surface: '#FFFFFF',
  subtle: '#EEF3F7',
  border: '#D9E2EA',
  text: '#24323D',         // Winter
  muted: '#5B6B7A',
  pillar: {
    safety: '#C62828',
    productivity: '#B45309',
    experience: '#0F766E',
  },
  good: '#047857',
  series: ['#29B5E8', '#11567F', '#FF9F36', '#7D44CF', '#D45B90', '#71D3DC', '#8A999E'],
} as const
