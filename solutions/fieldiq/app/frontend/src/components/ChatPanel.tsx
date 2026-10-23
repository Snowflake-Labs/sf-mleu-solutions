import { useState } from 'react'
import { Chat } from './Chat'

interface Props {
  initialPrompt?: string | null
  onConsumed?: () => void
}

export function ChatPanel({ initialPrompt, onConsumed }: Props) {
  const [open, setOpen] = useState(false)

  return (
    <>
      {!open && (
        <button
          onClick={() => setOpen(true)}
          className="fixed bottom-6 right-6 z-40 w-14 h-14 rounded-full bg-gradient-to-br from-apex-red to-orange-500 text-white shadow-xl shadow-apex-red/30 hover:scale-110 transition-transform flex items-center justify-center"
        >
          <svg viewBox="0 0 24 24" className="w-6 h-6" fill="currentColor">
            <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>
          </svg>
        </button>
      )}

      {open && (
        <div className="fixed inset-0 z-50 flex">
          <div className="flex-1 bg-black/30 backdrop-blur-sm" onClick={() => setOpen(false)} />
          <div className="w-full max-w-2xl bg-white shadow-2xl flex flex-col animate-slide-in-right">
            <div className="border-b border-canvas-300 px-5 py-3 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="apex-corner w-8 h-6" />
                <div>
                  <div className="text-sm font-semibold text-apex-dark">FieldIQ</div>
                  <div className="text-[11px] text-apex-gray">Cortex Agent · Analyst + Search + Actions</div>
                </div>
              </div>
              <button onClick={() => setOpen(false)} className="p-2 rounded-lg hover:bg-canvas-100 transition-colors">
                <svg viewBox="0 0 24 24" className="w-5 h-5 text-canvas-500" fill="currentColor">
                  <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
                </svg>
              </button>
            </div>
            <Chat initialPrompt={initialPrompt} onConsumed={onConsumed} className="flex-1 min-h-0" />
          </div>
        </div>
      )}
    </>
  )
}
