'use server';

import { revalidatePath } from 'next/cache';
import { ApiService } from '@/lib/api';
import { createClient } from '@/lib/supabase/server';
import type {
  CreateRelationshipInput,
  KnowledgeEdge,
  KnowledgeGraphData,
} from '@/types';

function safeRevalidatePath(path: string) {
  try {
    revalidatePath(path);
  } catch {
    // Graceful no-op in test environments without Next.js request context
  }
}

export async function getKnowledgeGraphAction(params?: {
  focusId?: string;
  depth?: number;
  limit?: number;
  type?: string;
  relationshipType?: string;
}): Promise<{ success: boolean; data?: KnowledgeGraphData; error?: string }> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const data = await ApiService.getKnowledgeGraph(params);
    return { success: true, data };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load personal knowledge graph';
    return { success: false, error: msg };
  }
}

export async function createRelationshipAction(
  input: CreateRelationshipInput
): Promise<{ success: boolean; relationship?: KnowledgeEdge; error?: string }> {
  if (!input.sourceId?.trim() || !input.targetId?.trim()) {
    return { success: false, error: 'sourceId and targetId are required' };
  }

  if (input.sourceId.trim() === input.targetId.trim()) {
    return { success: false, error: 'Self-referential relationships are not permitted' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const relationship = await ApiService.createRelationship(input);
    safeRevalidatePath('/knowledge-graph');
    return { success: true, relationship };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to create relationship';
    return { success: false, error: msg };
  }
}

export async function updateRelationshipAction(
  id: string,
  updates: { relationshipType?: string; confidence?: string; metadata?: Record<string, unknown> }
): Promise<{ success: boolean; relationship?: KnowledgeEdge | null; error?: string }> {
  if (!id || !id.trim()) {
    return { success: false, error: 'id is required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const relationship = await ApiService.updateRelationship(id.trim(), updates);
    safeRevalidatePath('/knowledge-graph');
    return { success: true, relationship };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to update relationship';
    return { success: false, error: msg };
  }
}

export async function deleteRelationshipAction(
  id: string
): Promise<{ success: boolean; error?: string }> {
  if (!id || !id.trim()) {
    return { success: false, error: 'id is required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const success = await ApiService.deleteRelationship(id.trim());
    safeRevalidatePath('/knowledge-graph');
    return { success };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to delete relationship';
    return { success: false, error: msg };
  }
}

export async function getNodeNeighborsAction(
  nodeId: string,
  params?: { depth?: number; limit?: number }
): Promise<{ success: boolean; data?: KnowledgeGraphData; error?: string }> {
  if (!nodeId || !nodeId.trim()) {
    return { success: false, error: 'nodeId is required' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    const data = await ApiService.getNodeNeighbors(nodeId.trim(), params);
    return { success: true, data };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Failed to load node neighbors';
    return { success: false, error: msg };
  }
}

