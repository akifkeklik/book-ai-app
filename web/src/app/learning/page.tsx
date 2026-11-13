'use client';

import React, { Suspense } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { useAuth } from '@/components/AuthProvider';
import { usePreferences } from '@/components/PreferencesProvider';
import { LearningDashboard } from '@/components/LearningDashboard';
import { Lock, Loader2 } from 'lucide-react';

function LearningDashboardWithParams() {
  const searchParams = useSearchParams();
  const concept = searchParams.get('concept') || undefined;
  const pathId = searchParams.get('path_id') || undefined;

  return (
    <LearningDashboard
      initialConceptFilter={concept}
      initialPathId={pathId}
    />
  );
}

export default function LearningPage() {
  const { user, loading: authLoading } = useAuth();
  const { t } = usePreferences();

  if (authLoading) {
    return (
      <div className="container mx-auto px-4 py-12 max-w-7xl animate-pulse space-y-6">
        <div className="h-10 w-64 bg-[var(--surface-raised)] rounded-xl" />
        <div className="h-96 bg-[var(--surface-raised)] rounded-2xl" />
      </div>
    );
  }

  if (!user) {
    return (
      <div className="container mx-auto px-4 py-20 max-w-md text-center space-y-6">
        <div className="w-16 h-16 rounded-full bg-[var(--accent)]/10 text-[var(--accent)] mx-auto flex items-center justify-center">
          <Lock className="w-8 h-8" />
        </div>
        <div className="space-y-2">
          <h1 className="text-2xl font-bold text-[var(--text)]">
            {t('learning_title')}
          </h1>
          <p className="text-sm text-[var(--text-secondary)]">
            {t('learning_login_required')}
          </p>
        </div>
        <div className="flex items-center justify-center gap-3">
          <Link
            href="/login?redirect=/learning"
            className="px-5 py-2.5 rounded-xl bg-[var(--accent)] text-white text-sm font-semibold hover:opacity-90 transition shadow-sm"
          >
            {t('nav_login')}
          </Link>
          <Link
            href="/signup?redirect=/learning"
            className="px-5 py-2.5 rounded-xl bg-[var(--surface)] border border-[var(--border)] text-[var(--text)] text-sm font-semibold hover:bg-[var(--surface-raised)] transition"
          >
            {t('nav_signup')}
          </Link>
        </div>
      </div>
    );
  }

  return (
    <main className="container mx-auto px-4 py-8 max-w-7xl">
      <Suspense fallback={
        <div className="p-12 text-center flex flex-col items-center justify-center gap-3">
          <Loader2 className="w-6 h-6 animate-spin text-[var(--accent)]" />
          <p className="text-sm text-[var(--text-secondary)]">{t('learning_loading')}</p>
        </div>
      }>
        <LearningDashboardWithParams />
      </Suspense>
    </main>
  );
}
