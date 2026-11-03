import { Skeleton, BookGridSkeleton } from '@/components/Skeleton';

export default function CatalogLoading() {
  return (
    <div className="container animate-fade-in" style={{ paddingBottom: '4rem' }} aria-busy="true">
      {/* Header and Search Skeleton */}
      <div style={{ marginBottom: '2.5rem' }}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            flexWrap: 'wrap',
            gap: '1.5rem',
            marginBottom: '1.5rem',
          }}
        >
          <div>
            <Skeleton width="280px" height="2.5rem" style={{ marginBottom: '0.5rem' }} />
            <Skeleton width="420px" height="1.25rem" />
          </div>
          <Skeleton width="380px" height="46px" borderRadius="12px" />
        </div>

        {/* Filter bar skeleton */}
        <div className="glass-panel" style={{ padding: '1rem 1.5rem', marginBottom: '2rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1rem' }}>
            <div style={{ display: 'flex', gap: '1rem' }}>
              <Skeleton width="140px" height="36px" borderRadius="8px" />
              <Skeleton width="180px" height="36px" borderRadius="8px" />
            </div>
            <Skeleton width="100px" height="24px" />
          </div>
        </div>
      </div>

      {/* Grid Skeleton */}
      <BookGridSkeleton count={8} />
    </div>
  );
}
