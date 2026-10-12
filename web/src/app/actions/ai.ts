'use server';

import { ApiService } from '@/lib/api';
import type { Book } from '@/types';

export interface AskAiResult {
  answer: string;
  referencedBooks: Book[];
  recommendations?: Book[];
  error?: string;
}

export async function askAI(query: string): Promise<AskAiResult> {
  try {
    const res = await ApiService.chatWithAI(query);
    return {
      answer: res.answer,
      referencedBooks: res.referencedBooks,
      recommendations: res.referencedBooks,
    };
  } catch (e: unknown) {
    return {
      answer: '',
      referencedBooks: [],
      recommendations: [],
      error: e instanceof Error ? e.message : 'Failed to chat with AI',
    };
  }
}
