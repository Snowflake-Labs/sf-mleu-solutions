import { ReactNode } from 'react'

interface Props {
  title: string
  insight: string
  source?: string
  children: ReactNode
  className?: string
}

export function ChartCard({ title, insight, source, children, className }: Props) {
  return (
    <div className={`bg-white border border-canvas-300 rounded-lg p-5 flex flex-col ${className || ''}`}>
      <div className="flex items-center gap-2 mb-1">
        <div className="w-1 h-5 bg-apex-red" />
        <h3 className="font-bold text-[15px] text-apex-dark leading-tight">{title}</h3>
      </div>
      <p className="text-[12px] italic text-canvas-500 mb-3 leading-snug">{insight}</p>
      <div className="flex-1 min-h-[220px]">{children}</div>
      {source && <div className="mt-2 pt-2 border-t border-canvas-200 text-[10px] text-canvas-500 uppercase tracking-wide">Source: {source}</div>}
    </div>
  )
}
