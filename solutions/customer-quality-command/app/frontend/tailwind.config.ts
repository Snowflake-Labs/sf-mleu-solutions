import type { Config } from 'tailwindcss'
import { THEME } from './src/config/brand'

export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          primary: THEME.primary,
          'primary-dark': THEME.primaryDark,
          accent: THEME.accent,
          navy: THEME.navy,
          bg: THEME.bg,
          surface: THEME.surface,
          subtle: THEME.subtle,
          border: THEME.border,
          text: THEME.text,
          muted: THEME.muted,
          good: THEME.good,
        },
        // S/P/E pillar status colors (AA contrast on white)
        pillar: {
          safety: THEME.pillar.safety,
          productivity: THEME.pillar.productivity,
          experience: THEME.pillar.experience,
        },
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'],
      },
      animation: {
        'fade-in-up': 'fadeInUp 0.6s ease-out both',
        'scale-in': 'scaleIn 0.4s ease-out both',
        'pulse-live': 'pulseLive 2s ease-in-out infinite',
      },
      keyframes: {
        fadeInUp: {
          from: { opacity: '0', transform: 'translateY(20px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
        scaleIn: {
          from: { opacity: '0', transform: 'scale(0.9)' },
          to: { opacity: '1', transform: 'scale(1)' },
        },
        pulseLive: {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0.4' },
        },
      },
    },
  },
  plugins: [],
} satisfies Config
