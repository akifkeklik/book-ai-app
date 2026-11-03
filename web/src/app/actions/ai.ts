'use server';

import { ApiService } from '@/lib/api';
import type { Book, AiAction } from '@/types';

export interface AskAiResult {
  answer: string;
  referencedBooks: Book[];
  recommendations?: Book[];
  status?: string;
  action?: AiAction | null;
  error?: string;
}

export async function askAI(query: string): Promise<AskAiResult> {
  try {
    const res = await ApiService.chatWithAI(query);
    return {
      answer: res.answer,
      referencedBooks: res.referencedBooks,
      recommendations: res.referencedBooks,
      status: res.status,
      action: res.action,
    };
  } catch (e: unknown) {
    return {
      answer: '',
      referencedBooks: [],
      recommendations: [],
      status: 'error',
      action: null,
      error: e instanceof Error ? e.message : 'Failed to chat with AI',
    };
  }
}
