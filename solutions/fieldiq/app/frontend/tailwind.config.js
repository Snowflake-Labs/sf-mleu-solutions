/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // FieldIQ / Apex Industrial — light theme
        apex: {
          red:    '#E03C31',  // primary red banner
          orange: '#F4511E',  // accent (slightly orange-shifted)
          dark:   '#1F2937',  // primary text
          gray:   '#6B7280',  // secondary text
          slate:  '#374151',
          50:     '#FFFAF7',
          100:    '#FEF2F2',  // very light red wash
          200:    '#FECACA',
          300:    '#FCA5A5',
          400:    '#F87171',
          500:    '#E03C31',  // brand red
          600:    '#C81E1A',
          700:    '#A6141A',
        },
        // Neutral grays (backgrounds + cards)
        canvas: {
          50:  '#FFFFFF',
          100: '#F9FAFB',
          200: '#F3F4F6',
          300: '#E5E7EB',
          400: '#D1D5DB',
          500: '#9CA3AF',
        },
        slate: {
          50: '#f8fafc', 100: '#f1f5f9', 200: '#e2e8f0', 300: '#cbd5e1',
          400: '#94a3b8', 500: '#64748b', 600: '#475569', 700: '#334155',
          800: '#1e293b', 900: '#0f172a',
        }
      },
      fontFamily: {
        sans: ['Inter','system-ui','sans-serif'],
        display: ['Inter','system-ui','sans-serif'],
        mono: ['JetBrains Mono','monospace'],
      },
      animation: {
        'fade-in':  'fadeIn 0.4s ease-out',
        'slide-up': 'slideUp 0.3s ease-out',
        'slide-in-right': 'slideInRight 0.3s ease-out',
        'scale-in': 'scaleIn 0.2s ease-out',
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
      keyframes: {
        fadeIn:  { '0%':{opacity:'0'}, '100%':{opacity:'1'} },
        slideUp: { '0%':{opacity:'0',transform:'translateY(10px)'},'100%':{opacity:'1',transform:'translateY(0)'} },
        slideInRight: { '0%':{opacity:'0',transform:'translateX(20px)'},'100%':{opacity:'1',transform:'translateX(0)'} },
        scaleIn: { '0%':{opacity:'0',transform:'scale(0.97)'},'100%':{opacity:'1',transform:'scale(1)'} },
      },
      // Angled red banner clip-path (used on Layout)
      clipPath: {
        'apex-corner': 'polygon(0 0, 88% 0, 100% 100%, 0 100%)',
      },
    },
  },
  plugins: [],
}
