import type { Metadata } from 'next';
import { PersonalizedDiscoveryView } from '@/components/PersonalizedDiscoveryView';

export const metadata: Metadata = {
  title: 'Personalized Discovery Hub | Libris',
  description: 'Curated recommendations shaped by your favorites, reading journey, and literary preferences.',
};

export default function PersonalizedDiscoveryPage() {
  return <PersonalizedDiscoveryView />;
}

