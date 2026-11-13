'use client';

import React from 'react';
import Link from 'next/link';
import { useAuth } from '@/components/AuthProvider';
import { usePreferences } from '@/components/PreferencesProvider';
import { KnowledgeGraphView } from '@/components/KnowledgeGraphView';
import { Lock } from 'lucide-react';

export default function KnowledgeGraphPage() {
  const { user, loading: authLoading } = useAuth();
  const { t } = usePreferences();

  if (authLoading) {
    return (
      <div className="container mx-auto px-4 py-12 max-w-7xl animate-pulse space-y-6">
        <div className="h-10 w-64 bg-surface-raised rounded-xl" />
        <div className="h-96 bg-surface-raised rounded-2xl" />
      </div>
    );
  }

  if (!user) {
    return (
      <div className="container mx-auto px-4 py-20 max-w-md text-center space-y-6">
        <div className="w-16 h-16 rounded-full bg-primary/10 text-primary mx-auto flex items-center justify-center">
          <Lock className="w-8 h-8" />
        </div>
        <div className="space-y-2">
          <h1 className="text-2xl font-bold text-foreground">
            {t('kg_title')}
          </h1>
          <p className="text-sm text-muted-foreground">
            {t('kg_login_required')}
          </p>
        </div>
        <div className="flex items-center justify-center gap-3">
          <Link
            href="/login?redirect=/knowledge-graph"
            className="px-5 py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold hover:opacity-90 transition shadow-sm"
          >
            {t('nav_login')}
          </Link>
          <Link
            href="/signup?redirect=/knowledge-graph"
            className="px-5 py-2.5 rounded-xl bg-surface border border-border text-foreground text-sm font-semibold hover:bg-surface-raised transition"
          >
            {t('nav_signup')}
          </Link>
        </div>
      </div>
    );
  }

  return (
    <main className="container mx-auto px-4 py-8 max-w-7xl">
      <KnowledgeGraphView />
    </main>
  );
}

