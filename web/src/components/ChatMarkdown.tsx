'use client';

import { memo, useMemo, type ReactNode } from 'react';
import { parseMarkdown, type InlineNode } from '@/lib/ai_chat';

function renderInline(nodes: InlineNode[], keyPrefix = ''): ReactNode[] {
  return nodes.map((n, i) => {
    const key = `${keyPrefix}${i}`;
    switch (n.type) {
      case 'strong':
        return <strong key={key}>{renderInline(n.children, `${key}-`)}</strong>;
      case 'em':
        return <em key={key}>{renderInline(n.children, `${key}-`)}</em>;
      case 'code':
        return <code key={key}>{n.text}</code>;
      default:
        return n.text;
    }
  });
}

/** Renders an AI answer's Markdown as React elements; model output is never injected as HTML. */
export const ChatMarkdown = memo(function ChatMarkdown({ content }: { content: string }) {
  const blocks = useMemo(() => parseMarkdown(content), [content]);
  return (
    <div className="chat-md">
      {blocks.map((b, i) => {
        switch (b.type) {
          case 'heading': {
            const Tag = `h${b.level}` as 'h2' | 'h3' | 'h4';
            return <Tag key={i}>{renderInline(b.children)}</Tag>;
          }
          case 'list': {
            const Tag = b.ordered ? 'ol' : 'ul';
            return (
              <Tag key={i}>
                {b.items.map((item, j) => (
                  <li key={j}>{renderInline(item)}</li>
                ))}
              </Tag>
            );
          }
          case 'code':
            return (
              <pre key={i} data-lang={b.lang || undefined}>
                <code>{b.text}</code>
              </pre>
            );
          case 'quote':
            return <blockquote key={i}>{renderInline(b.children)}</blockquote>;
          default:
            return <p key={i}>{renderInline(b.children)}</p>;
        }
      })}
    </div>
  );
});
