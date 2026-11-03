import datetime
import logging
from typing import Any, Dict, List, Optional

from ...domain.ports import BookDataPort, UserNoteRepository

logger = logging.getLogger(__name__)

NOTE_TYPE_LABELS = {
    "personal_note": "Kişisel Not / Personal Note",
    "key_takeaway": "Önemli Çıkarım / Key Takeaway",
    "question": "Soru / Question",
}


class ExportNotesUseCase:
    def __init__(
        self,
        note_repo: UserNoteRepository,
        book_data_port: Optional[BookDataPort] = None,
    ):
        self._note_repo = note_repo
        self._book_data_port = book_data_port

    def execute(
        self,
        user_id: str,
        book_id: Optional[str] = None,
        export_format: str = "markdown",
    ) -> Dict[str, Any]:
        if not user_id or not user_id.strip():
            raise ValueError("user_id is required")

        clean_user_id = user_id.strip()
        clean_book_id = book_id.strip() if book_id and book_id.strip() else None
        clean_format = (export_format or "markdown").strip().lower()

        if clean_format not in {"markdown", "md"}:
            raise ValueError(f"Unsupported format: '{export_format}'. Supported: markdown")

        # Fetch all notes for user (up to 1000 for export safety)
        notes = self._note_repo.get_user_notes(
            user_id=clean_user_id,
            book_id=clean_book_id,
            limit=1000,
            offset=0,
        )

        # Batch enrich book metadata
        book_map: Dict[str, Dict[str, Any]] = {}
        if self._book_data_port and notes:
            unique_bids = list({str(n.get("book_id", "")).strip() for n in notes if n.get("book_id")})
            if unique_bids:
                try:
                    books = self._book_data_port.get_books_by_isbns(unique_bids)
                    book_map = {
                        str(b.get("isbn13") or b.get("isbn") or "").strip(): b
                        for b in (books or [])
                    }
                except Exception as e:
                    logger.warning(f"Failed to enrich export notes with books: {e}")

        # Group notes by book
        grouped_notes: Dict[str, List[Dict[str, Any]]] = {}
        for note in notes:
            bid = str(note.get("book_id", "Unknown Book")).strip()
            grouped_notes.setdefault(bid, []).append(note)

        now_utc = datetime.datetime.now(datetime.timezone.utc)
        timestamp_str = now_utc.strftime("%Y-%m-%d %H:%M UTC")
        file_timestamp = now_utc.strftime("%Y%m%d_%H%M%S")

        # Build Markdown content safely
        lines: List[str] = []
        lines.append("# Libris — Öğrenme Notları ve Çıkarımlar / Learning Notes Export")
        lines.append(f"- **Dışa Aktarma Tarihi / Export Date:** {timestamp_str}")
        lines.append(f"- **Toplam Not Sayısı / Total Notes:** {len(notes)}")
        if clean_book_id:
            lines.append(f"- **Filtrelenen Kitap / Filtered Book:** {clean_book_id}")
        lines.append("\n---\n")

        if not notes:
            lines.append("*Dışa aktarılacak herhangi bir not bulunamadı / No learning notes found.*")
        else:
            for bid, b_notes in grouped_notes.items():
                b_info = book_map.get(bid, {})
                title = b_info.get("title") or b_notes[0].get("bookTitle") or f"Kitap / Book ({bid})"
                author = b_info.get("authors") or b_notes[0].get("bookAuthor") or "Bilinmeyen Yazar / Unknown Author"

                lines.append(f"## 📖 {title}")
                lines.append(f"- **Yazar / Author:** {author}")
                lines.append(f"- **ISBN:** `{bid}`\n")

                for n in b_notes:
                    ntype = n.get("note_type", "personal_note")
                    type_label = NOTE_TYPE_LABELS.get(ntype, ntype.capitalize())
                    created = n.get("created_at") or "N/A"
                    content = n.get("content", "").strip()

                    lines.append(f"### 📝 {type_label}")
                    lines.append(f"*Tarih / Date: {created}*")
                    lines.append(f"\n{content}\n")

                lines.append("---\n")

        markdown_text = "\n".join(lines)
        filename = f"libris_notes_{clean_book_id or 'all'}_{file_timestamp}.md"

        return {
            "filename": filename,
            "content": markdown_text,
            "mime_type": "text/markdown; charset=utf-8",
            "total": len(notes),
        }

