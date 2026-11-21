'use client';

import { useSyncExternalStore } from 'react';
import { CHAT_HISTORY_KEY, loadConversations, saveConversations, type Conversation } from '@/lib/ai_chat';

// A tiny external store over localStorage. The server snapshot is empty, so the first client
// render matches the server HTML and history appears right after hydration without a flash.
const EMPTY: Conversation[] = [];
const listeners = new Set<() => void>();
let cache: Conversation[] | null = null;

function getSnapshot(): Conversation[] {
  if (cache === null) cache = loadConversations();
  return cache;
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  const onStorage = (e: StorageEvent) => {
    if (e.key === CHAT_HISTORY_KEY) {
      cache = null;
      listener();
    }
  };
  window.addEventListener('storage', onStorage);
  return () => {
    listeners.delete(listener);
    window.removeEventListener('storage', onStorage);
  };
}

export function readConversations(): Conversation[] {
  return getSnapshot();
}

export function writeConversations(next: Conversation[]): void {
  cache = next;
  saveConversations(next);
  listeners.forEach((l) => l());
}

export function useConversationHistory(): Conversation[] {
  return useSyncExternalStore(subscribe, getSnapshot, () => EMPTY);
}
