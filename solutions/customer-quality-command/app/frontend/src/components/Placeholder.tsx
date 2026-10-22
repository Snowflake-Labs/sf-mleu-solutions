import PageHeader from './PageHeader'

export default function Placeholder({ title, subtitle, doc }: { title: string; subtitle?: string; doc?: string }) {
  return (
    <div className="flex-1">
      <PageHeader title={title} subtitle={subtitle} />
      <div className="p-8">
        <div className="rounded-lg border border-dashed border-brand-border bg-brand-surface p-10 text-center animate-fade-in-up">
          <div className="text-brand-primary text-3xl mb-3">⬡</div>
          <p className="text-brand-text">Scaffolded — implementation pending.</p>
          {doc && <p className="text-xs text-brand-muted mt-2">Spec: {doc}</p>}
        </div>
      </div>
    </div>
  )
}
