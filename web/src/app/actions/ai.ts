'use server';

import { ApiService } from '@/lib/api';
import type { Book } from '@/types';

export async function askAI(query: string): Promise<{ answer: string; recommendations?: Book[], error?: string }> {
  try {
    const res = await ApiService.chatWithAI(query);
    return res;
  } catch (e: unknown) {
    return { answer: '', error: e instanceof Error ? e.message : 'Failed to chat with AI' };
  }
}
