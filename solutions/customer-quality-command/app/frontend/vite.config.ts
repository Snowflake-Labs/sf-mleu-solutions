import { createHash } from 'node:crypto'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { ANCHOR } from './src/config/brand'

// Story Mode anchor issue ids. Mirrors the platform's deterministic issue key:
// MD5(model || '|' || system_group_cd || '|' || failure_mode_cd)
// (platform/ddl/048_analytics_issue.sql, platform/ml/module4_issue_clustering.py).
const issueId = (failureMode: string) =>
  createHash('md5').update(`${ANCHOR.model}|${ANCHOR.systemGroup}|${failureMode}`).digest('hex')

export default defineConfig({
  plugins: [react()],
  define: {
    __STORY_SAFETY_ISSUE__: JSON.stringify(issueId('SUDDEN_SHUTDOWN')),
    __STORY_MONEY_ISSUE__: JSON.stringify(issueId('POWER_LOSS')),
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
})
