"""
Maathai Desktop — Knowledge Browser View (PyQt6)

Browse the offline agricultural knowledge base by category.
Search by keyword. View full article text.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QSplitter,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.rag.retriever import Retriever

logger = logging.getLogger(__name__)

KNOWLEDGE_BASE_DIR = Path(__file__).parent.parent.parent / "assets" / "knowledge_base"
CATEGORIES = ["all", "crops", "pests", "soil", "markets", "calendars"]


class KnowledgeView(QWidget):
    def __init__(self, retriever: Retriever) -> None:
        super().__init__()
        self.retriever = retriever
        self._all_entries: list[dict] = []
        self._search_timer = QTimer()
        self._search_timer.setSingleShot(True)
        self._search_timer.timeout.connect(self._apply_filter)

        self._setup_ui()
        self._load_entries()

    def _setup_ui(self) -> None:
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        # Left panel: search + filter + list
        left = QWidget()
        left.setFixedWidth(300)
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(8, 8, 8, 8)

        # Search
        self._search = QLineEdit()
        self._search.setPlaceholderText("Search articles…")
        self._search.textChanged.connect(self._on_search_changed)
        left_layout.addWidget(self._search)

        # Category filter
        self._category = QComboBox()
        self._category.addItems([c.capitalize() for c in CATEGORIES])
        self._category.currentIndexChanged.connect(self._apply_filter)
        left_layout.addWidget(self._category)

        # Article list
        self._list = QListWidget()
        self._list.currentItemChanged.connect(self._on_item_selected)
        left_layout.addWidget(self._list)

        self._count_label = QLabel("0 articles")
        left_layout.addWidget(self._count_label)

        layout.addWidget(left)

        # Right panel: article content
        self._content = QTextEdit()
        self._content.setReadOnly(True)
        self._content.setStyleSheet("QTextEdit { padding: 16px; }")
        layout.addWidget(self._content, stretch=1)

    def _load_entries(self) -> None:
        for cat in CATEGORIES[1:]:  # skip "all"
            cat_dir = KNOWLEDGE_BASE_DIR / cat
            if not cat_dir.exists():
                continue
            for json_file in sorted(cat_dir.glob("*.json")):
                try:
                    entries = json.loads(json_file.read_text(encoding="utf-8"))
                    for entry in entries:
                        if isinstance(entry, dict):
                            entry["category"] = cat
                            self._all_entries.append(entry)
                except Exception as exc:
                    logger.error("Failed to load %s: %s", json_file, exc)

        self._apply_filter()

    def _on_search_changed(self) -> None:
        self._search_timer.start(300)  # debounce 300ms

    def _apply_filter(self) -> None:
        query = self._search.text().lower()
        cat_idx = self._category.currentIndex()
        cat = CATEGORIES[cat_idx]

        filtered = [
            e for e in self._all_entries
            if (cat == "all" or e.get("category") == cat)
            and (
                not query
                or query in e.get("title", "").lower()
                or query in e.get("content", "").lower()
                or any(query in t.lower() for t in e.get("tags", []))
            )
        ]

        self._list.clear()
        for entry in filtered:
            item = QListWidgetItem(f"[{entry.get('category', '')}] {entry.get('title', '')}")
            item.setData(Qt.ItemDataRole.UserRole, entry)
            self._list.addItem(item)

        self._count_label.setText(f"{len(filtered)} article{'s' if len(filtered) != 1 else ''}")

    def _on_item_selected(self, current: QListWidgetItem | None, _) -> None:
        if current is None:
            return
        entry = current.data(Qt.ItemDataRole.UserRole)
        if not entry:
            return

        title = entry.get("title", "")
        content = entry.get("content", "")
        category = entry.get("category", "")
        tags = entry.get("tags", [])

        display = f"# {title}\n\n"
        display += f"**Category:** {category}  \n"
        if tags:
            display += f"**Tags:** {', '.join(tags)}\n\n"
        display += "---\n\n"
        display += content

        self._content.setMarkdown(display)
