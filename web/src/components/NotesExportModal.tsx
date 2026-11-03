'use client';

import React, { useState, useEffect } from 'react';
import { Download, Copy, Printer, Check, X, Loader2, FileText } from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import { exportNotesAction } from '@/app/actions/notes';

export interface NotesExportModalProps {
  isOpen: boolean;
  onClose: () => void;
  bookId?: string;
}

export function NotesExportModal({ isOpen, onClose, bookId }: NotesExportModalProps) {
  const { t } = usePreferences();
  const [loading, setLoading] = useState<boolean>(true);
  const [content, setContent] = useState<string>('');
  const [filename, setFilename] = useState<string>('libris_notes.md');
  const [copied, setCopied] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;

    let active = true;
    async function fetchExport() {
      setLoading(true);
      setError(null);
      try {
        const res = await exportNotesAction(bookId);
        if (active) {
          if (res.success && res.content) {
            setContent(res.content);
            if (res.filename) setFilename(res.filename);
          } else {
            setError(res.error || 'Failed to export notes');
          }
        }
      } catch (err) {
        if (active) setError(err instanceof Error ? err.message : 'Export failed');
      } finally {
        if (active) setLoading(false);
      }
    }

    fetchExport();
    return () => {
      active = false;
    };
  }, [isOpen, bookId]);

  if (!isOpen) return null;

  const handleCopy = () => {
    if (!content) return;
    navigator.clipboard.writeText(content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDownload = () => {
    if (!content) return;
    const blob = new Blob([content], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  const handlePrint = () => {
    const printWindow = window.open('', '_blank');
    if (!printWindow) return;

    printWindow.document.write(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>${filename.replace('.md', '')}</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
              line-height: 1.6;
              padding: 40px;
              color: #1a1a1a;
              max-width: 800px;
              margin: 0 auto;
            }
            h1 { font-size: 24px; border-bottom: 2px solid #eaeaea; padding-bottom: 8px; margin-bottom: 16px; }
            h2 { font-size: 18px; color: #2563eb; margin-top: 24px; }
            h3 { font-size: 14px; color: #7c3aed; margin-top: 16px; margin-bottom: 4px; }
            pre { background: #f8fafc; padding: 16px; border-radius: 8px; white-space: pre-wrap; font-family: monospace; font-size: 13px; }
            @media print {
              body { padding: 0; }
              button { display: none; }
            }
          </style>
        </head>
        <body>
          <pre>${content.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</pre>
        </body>
      </html>
    `);
    printWindow.document.close();
    printWindow.focus();
    setTimeout(() => {
      printWindow.print();
    }, 250);
  };

  return (
    <div
      data-testid="notes-export-modal"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
    >
      <div
        className="w-full max-w-2xl bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl flex flex-col max-h-[85vh] overflow-hidden"
        role="dialog"
        aria-modal="true"
        aria-labelledby="export-modal-title"
      >
        {/* Modal Header */}
        <div className="flex items-center justify-between p-5 border-b border-[var(--border)]">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-lg bg-[var(--accent)]/10 text-[var(--accent)] flex items-center justify-center">
              <FileText className="w-4 h-4" />
            </div>
            <div>
              <h2 id="export-modal-title" className="text-base font-bold text-[var(--text)]">
                {t('export_notes')}
              </h2>
              <p className="text-xs text-[var(--text-secondary)]">{t('export_notes_desc')}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg text-[var(--text-secondary)] hover:text-[var(--text)] hover:bg-[var(--border)]/30 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Body */}
        <div className="p-5 flex-1 overflow-y-auto">
          {loading ? (
            <div className="h-60 flex flex-col items-center justify-center gap-3">
              <Loader2 className="w-6 h-6 animate-spin text-[var(--accent)]" />
              <p className="text-sm text-[var(--text-secondary)]">{t('loading')}</p>
            </div>
          ) : error ? (
            <div className="p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-600 dark:text-red-400 text-sm">
              {error}
            </div>
          ) : (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-[var(--bg)] border border-[var(--border)] font-mono text-xs text-[var(--text)] overflow-x-auto whitespace-pre-wrap max-h-80 leading-relaxed">
                {content}
              </div>
            </div>
          )}
        </div>

        {/* Modal Actions */}
        <div className="p-4 border-t border-[var(--border)] bg-[var(--surface-variant)] flex flex-wrap items-center justify-between gap-2">
          <div className="text-xs text-[var(--text-secondary)]">
            <span>{filename}</span>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              disabled={loading || !content}
              onClick={handleCopy}
              className="px-3 py-1.5 rounded-lg border border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--border)]/20 text-xs font-medium text-[var(--text)] flex items-center gap-1.5 transition-colors disabled:opacity-50"
            >
              {copied ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
              <span>{copied ? t('markdown_copied') : t('copy_markdown')}</span>
            </button>

            <button
              type="button"
              disabled={loading || !content}
              onClick={handlePrint}
              className="px-3 py-1.5 rounded-lg border border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--border)]/20 text-xs font-medium text-[var(--text)] flex items-center gap-1.5 transition-colors disabled:opacity-50"
            >
              <Printer className="w-3.5 h-3.5" />
              <span>{t('print_preview')}</span>
            </button>

            <button
              type="button"
              disabled={loading || !content}
              onClick={handleDownload}
              className="px-3.5 py-1.5 rounded-lg bg-[var(--accent)] text-white hover:opacity-90 text-xs font-semibold flex items-center gap-1.5 shadow-sm transition-opacity disabled:opacity-50"
            >
              <Download className="w-3.5 h-3.5" />
              <span>{t('download_markdown')}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

