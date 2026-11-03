import { BookGridSkeleton } from '@/components/Skeleton';

export default function PersonalizedDiscoveryLoading() {
  return (
    <main className="container" style={{ padding: '2.5rem 1rem 5rem' }}>
      <div style={{ marginBottom: '2rem' }}>
        <div
          className="skeleton animate-pulse"
          style={{ width: '160px', height: '24px', borderRadius: '9999px', marginBottom: '0.75rem' }}
        />
        <div
          className="skeleton animate-pulse"
          style={{ width: '320px', height: '40px', borderRadius: '8px', marginBottom: '0.5rem' }}
        />
        <div
          className="skeleton animate-pulse"
          style={{ width: '480px', height: '20px', borderRadius: '6px' }}
        />
      </div>

      <div
        className="glass-panel"
        style={{ height: '70px', borderRadius: '16px', marginBottom: '2rem' }}
      />

      <BookGridSkeleton count={8} />
    </main>
  );
}

