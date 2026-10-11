'use client';

import { BookOpen } from 'lucide-react';

interface BookCoverFallbackProps {
  title: string;
  authors?: string;
  className?: string;
  height?: string | number;
  style?: React.CSSProperties;
}

const GRADIENTS = [
  'linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%)',
  'linear-gradient(135deg, #4c1d95 0%, #8b5cf6 100%)',
  'linear-gradient(135deg, #064e3b 0%, #10b981 100%)',
  'linear-gradient(135deg, #7c2d12 0%, #f97316 100%)',
  'linear-gradient(135deg, #831843 0%, #ec4899 100%)',
  'linear-gradient(135deg, #0f172a 0%, #334155 100%)',
];

function getGradient(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash);
  }
  const index = Math.abs(hash) % GRADIENTS.length;
  return GRADIENTS[index];
}

export function BookCoverFallback({ title, authors, className, height, style }: BookCoverFallbackProps) {
  const gradient = getGradient(title || 'book');

  return (
    <div
      className={className}
      style={{
        background: gradient,
        width: '100%',
        height: height || '100%',
        borderRadius: '12px',
        padding: '1.25rem 1rem',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between',
        color: '#ffffff',
        position: 'relative',
        overflow: 'hidden',
        boxShadow: 'inset 4px 0 10px rgba(0,0,0,0.3)',
        ...style,
      }}
    >
      {/* Decorative Book Spine Line */}
      <div
        style={{
          position: 'absolute',
          top: 0,
          left: '12px',
          bottom: 0,
          width: '2px',
          background: 'rgba(255, 255, 255, 0.2)',
        }}
      />

      <div style={{ paddingLeft: '8px' }}>
        <h4
          style={{
            fontFamily: "'Playfair Display', serif",
            fontSize: '0.95rem',
            lineHeight: 1.25,
            fontWeight: 700,
            overflow: 'hidden',
            display: '-webkit-box',
            WebkitLineClamp: 3,
            WebkitBoxOrient: 'vertical',
            wordBreak: 'break-word',
            textShadow: '0 1px 3px rgba(0,0,0,0.4)',
          }}
          title={title}
        >
          {title}
        </h4>
        {authors && (
          <p
            style={{
              fontSize: '0.75rem',
              color: 'rgba(255, 255, 255, 0.8)',
              marginTop: '0.35rem',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {authors}
          </p>
        )}
      </div>

      <div
        style={{
          display: 'flex',
          justifyContent: 'flex-end',
          alignItems: 'flex-end',
          opacity: 0.6,
          paddingRight: '4px',
        }}
      >
        <BookOpen size={20} color="#ffffff" />
      </div>
    </div>
  );
}
