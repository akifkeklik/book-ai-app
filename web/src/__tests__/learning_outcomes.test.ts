import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  normalizeReviewItem,
  normalizeReviewAttempt,
  normalizeLearningProgress,
} from '../lib/normalizers';
import { DICTIONARIES, translate } from '../lib/i18n';
import {
  createLearningItemAction,
  submitLearningAttemptAction,
  deleteLearningItemAction,
} from '../app/actions/learning';

describe('Sprint 28: Learning Outcomes Intelligence Normalizers', () => {
  it('normalizeReviewItem correctly transforms backend DTO to camelCase', () => {
    const raw = {
      id: 'rev-item-123',
      user_id: 'user-456',
      title: 'CAP Theorem Review',
      concept: 'Distributed Systems',
      question: 'What is CAP?',
      answer: 'Consistency, Availability, Partition tolerance',
      explanation: 'Brewer theorem 2000',
      source_type: 'key_takeaway',
      source_id: 'note-789',
      book_id: '9780143127741',
      stage: 3,
      interval_days: 7,
      next_review_at: '2026-11-04T12:00:00Z',
      last_reviewed_at: '2026-10-28T12:00:00Z',
      total_reviews: 4,
      successful_reviews: 3,
      status: 'active',
      priority: 105,
      recommendation_reason: 'Review is overdue for retention reinforcement',
      recommendation_reason_key: 'review_overdue',
      book: {
        isbn13: '9780143127741',
        title: 'Designing Data-Intensive Applications',
        authors: 'Martin Kleppmann',
      },
    };

    const item = normalizeReviewItem(raw);
    assert.strictEqual(item.id, 'rev-item-123');
    assert.strictEqual(item.userId, 'user-456');
    assert.strictEqual(item.concept, 'Distributed Systems');
    assert.strictEqual(item.sourceType, 'key_takeaway');
    assert.strictEqual(item.stage, 3);
    assert.strictEqual(item.intervalDays, 7);
    assert.strictEqual(item.priority, 105);
    assert.strictEqual(item.recommendationReasonKey, 'review_overdue');
    assert.ok(item.book);
    assert.strictEqual(item.book?.title, 'Designing Data-Intensive Applications');
  });

  it('normalizeReviewItem handles null and missing fields safely', () => {
    const item = normalizeReviewItem({});
    assert.strictEqual(item.id, '');
    assert.strictEqual(item.stage, 1);
    assert.strictEqual(item.intervalDays, 1);
    assert.strictEqual(item.totalReviews, 0);
    assert.strictEqual(item.status, 'active');
    assert.strictEqual(item.book, null);
  });

  it('normalizeReviewAttempt correctly maps attempt record', () => {
    const raw = {
      id: 'att-1',
      user_id: 'u-1',
      item_id: 'i-1',
      outcome: 'remembered',
      response_text: 'My recall draft',
      is_correct: true,
      stage_before: 2,
      stage_after: 3,
      reviewed_at: '2026-10-28T12:00:00Z',
      item_title: 'Raft Consensus',
      concept: 'Distributed Systems',
    };

    const attempt = normalizeReviewAttempt(raw);
    assert.strictEqual(attempt.id, 'att-1');
    assert.strictEqual(attempt.outcome, 'remembered');
    assert.strictEqual(attempt.isCorrect, true);
    assert.strictEqual(attempt.stageBefore, 2);
    assert.strictEqual(attempt.stageAfter, 3);
    assert.strictEqual(attempt.concept, 'Distributed Systems');
  });

  it('normalizeLearningProgress correctly transforms progress metrics and difficult concepts', () => {
    const raw = {
      mastery_score: 78,
      mastery_level: 'proficient',
      total_items: 12,
      reviews_due: 3,
      reviews_completed: 18,
      successful_recalls: 15,
      struggled_recalls: 3,
      retention_rate: 0.83,
      concepts_count: 4,
      difficult_concepts: [
        {
          concept: 'Distributed Systems',
          total_items: 4,
          total_attempts: 6,
          successful_recalls: 3,
          struggled_recalls: 3,
          retention_rate: 0.5,
          average_stage: 2.2,
          due_items: 1,
          needs_review: true,
        },
      ],
      recent_activity: [
        {
          id: 'a-1',
          item_id: 'i-1',
          outcome: 'remembered',
          is_correct: true,
          stage_before: 1,
          stage_after: 2,
        },
      ],
      active_streak_days: 5,
      algorithm_version: 'v1',
    };

    const prog = normalizeLearningProgress(raw);
    assert.strictEqual(prog.masteryScore, 78);
    assert.strictEqual(prog.masteryLevel, 'proficient');
    assert.strictEqual(prog.totalItems, 12);
    assert.strictEqual(prog.reviewsDue, 3);
    assert.strictEqual(prog.reviewsCompleted, 18);
    assert.strictEqual(prog.retentionRate, 0.83);
    assert.strictEqual(prog.activeStreakDays, 5);
    assert.strictEqual(prog.algorithmVersion, 'v1');
    assert.strictEqual(prog.difficultConcepts.length, 1);
    assert.strictEqual(prog.difficultConcepts[0].concept, 'Distributed Systems');
    assert.strictEqual(prog.difficultConcepts[0].needsReview, true);
    assert.strictEqual(prog.recentActivity.length, 1);
  });
});

describe('Sprint 28: Learning Outcomes Server Actions Validation', () => {
  it('createLearningItemAction rejects empty or missing required inputs', async () => {
    const res = await createLearningItemAction({
      title: '',
      concept: 'Math',
      question: '2+2?',
      answer: '4',
    });
    assert.strictEqual(res.success, false);
    assert.ok(res.error?.includes('required'));
  });

  it('submitLearningAttemptAction rejects invalid outcomes', async () => {
    const res = await submitLearningAttemptAction({
      itemId: 'some-id',
      outcome: 'perfect' as unknown as 'remembered' | 'struggled',
    });
    assert.strictEqual(res.success, false);
    assert.ok(res.error?.includes("outcome must be 'remembered' or 'struggled'"));
  });

  it('deleteLearningItemAction rejects empty itemId', async () => {
    const res = await deleteLearningItemAction('');
    assert.strictEqual(res.success, false);
    assert.strictEqual(res.error, 'itemId is required');
  });
});

describe('Sprint 28: Learning Outcomes Localization Parity (EN, TR, DE)', () => {
  const learningKeys = [
    'nav_learning',
    'learning_title',
    'learning_subtitle',
    'mastery_score',
    'mastery_level_insufficient_data',
    'mastery_level_novice',
    'mastery_level_practicing',
    'mastery_level_proficient',
    'mastery_level_mastered',
    'reviews_completed',
    'reviews_due',
    'retention_rate',
    'active_streak',
    'concepts_practiced',
    'difficult_concepts_title',
    'difficult_concepts_empty',
    'recent_activity_title',
    'recent_activity_empty',
    'active_recall_title',
    'active_recall_subtitle',
    'reveal_answer',
    'hide_answer',
    'your_answer_placeholder',
    'outcome_remembered',
    'outcome_struggled',
    'source_evidence',
    'next_scheduled_review',
    'create_question_button',
    'create_question_title',
    'question_title_label',
    'question_concept_label',
    'question_prompt_label',
    'question_answer_label',
    'question_explanation_label',
    'save_question_button',
    'empty_queue_title',
    'empty_queue_desc',
    'start_review_button',
    'review_overdue_reason',
    'previous_incorrect_reason',
    'learning_path_continuity_reason',
    'reinforcement_due_reason',
    'concept_practice_reason',
    'stage_label',
    'all_caught_up_banner',
    'view_concept_reviews',
    'start_path_reviews',
    'filter_by_path',
    'domain_integrity_disclaimer',
  ] as const;

  it('All Sprint 28 learning keys exist in EN, TR, and DE dictionaries', () => {
    for (const key of learningKeys) {
      assert.ok(key in DICTIONARIES.en, `Missing EN key: ${key}`);
      assert.ok(key in DICTIONARIES.tr, `Missing TR key: ${key}`);
      assert.ok(key in DICTIONARIES.de, `Missing DE key: ${key}`);

      const enVal = DICTIONARIES.en[key as keyof typeof DICTIONARIES.en];
      const trVal = DICTIONARIES.tr[key as keyof typeof DICTIONARIES.tr];
      const deVal = DICTIONARIES.de[key as keyof typeof DICTIONARIES.de];

      assert.ok(typeof enVal === 'string' && enVal.length > 0, `Empty EN value for ${key}`);
      assert.ok(typeof trVal === 'string' && trVal.length > 0, `Empty TR value for ${key}`);
      assert.ok(typeof deVal === 'string' && deVal.length > 0, `Empty DE value for ${key}`);
    }
  });

  it('translate function correctly formats parameterized strings', () => {
    const enStr = translate('en', 'next_scheduled_review', { days: 3, date: 'Nov 1' });
    assert.strictEqual(enStr, 'Next review in 3 days (Nov 1)');

    const trStr = translate('tr', 'next_scheduled_review', { days: 3, date: '1 Kas' });
    assert.strictEqual(trStr, 'Sonraki tekrar 3 gün sonra (1 Kas)');

    const deStr = translate('de', 'next_scheduled_review', { days: 3, date: '1. Nov' });
    assert.strictEqual(deStr, 'Nächste Wiederholung in 3 Tagen (1. Nov)');
  });
});

