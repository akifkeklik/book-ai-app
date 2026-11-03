import { Skeleton, BookGridSkeleton } from '@/components/Skeleton';

export default function RootLoading() {
  return (
    <div className="container" style={{ padding: '3.5rem 1.5rem', maxWidth: '1200px' }} aria-busy="true">
      {/* Hero Skeleton */}
      <div style={{ textAlign: 'center', maxWidth: '840px', margin: '0 auto 4.5rem' }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: '1.5rem' }}>
          <Skeleton width="220px" height="32px" borderRadius="9999px" />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.75rem', marginBottom: '1.5rem' }}>
          <Skeleton width="70%" height="3.5rem" />
          <Skeleton width="50%" height="3.5rem" />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.5rem', marginBottom: '2.5rem' }}>
          <Skeleton width="85%" height="1.25rem" />
          <Skeleton width="65%" height="1.25rem" />
        </div>
        <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', marginBottom: '3rem' }}>
          <Skeleton width="180px" height="52px" borderRadius="12px" />
          <Skeleton width="180px" height="52px" borderRadius="12px" />
        </div>
      </div>

      {/* Grid Skeleton */}
      <div style={{ marginBottom: '3rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
          <Skeleton width="240px" height="2rem" />
          <Skeleton width="100px" height="1.25rem" />
        </div>
        <BookGridSkeleton count={4} />
      </div>
    </div>
  );
}
