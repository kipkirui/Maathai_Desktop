"""
Maathai Desktop — Chat View (PyQt6)

Streaming agriculture Q&A panel with:
- Message history with markdown rendering
- Farm context (region / crop / season) injected into every prompt
- Swahili / English language toggle
- RAG source attribution (shows which knowledge base articles were used)
- Live typing indicator while streaming

Architecture mirrors ChatDetailScreen.dart from the Maathai mobile app.
Key difference: desktop uses threading instead of async Dart streams.
"""

from __future__ import annotations

import logging
import threading
from datetime import datetime
from typing import Optional

from PyQt6.QtCore import Qt, pyqtSignal, QObject
from PyQt6.QtGui import QFont, QTextCursor
from PyQt6.QtWidgets import (
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSplitter,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.llm.inference import LlamaInference
from src.llm.prompt_engine import PromptEngine
from src.rag.retriever import Retriever
from src.config import DEFAULT_LANGUAGE

logger = logging.getLogger(__name__)


class TokenEmitter(QObject):
    """Emits tokens and signals from background inference thread to UI thread."""
    token = pyqtSignal(str)
    done = pyqtSignal(list)    # RAG passages used
    error = pyqtSignal(str)


class ChatView(QWidget):
    def __init__(
        self,
        inference: LlamaInference,
        retriever: Retriever,
        prompt_engine: PromptEngine,
    ) -> None:
        super().__init__()
        self.inference = inference
        self.retriever = retriever
        self.prompt_engine = prompt_engine

        self._model_ready = False
        self._language = DEFAULT_LANGUAGE
        self._history: list[dict] = []  # [{role, content, timestamp}]
        self._generating = False
        self._emitter = TokenEmitter()

        self._setup_ui()
        self._connect_signals()

    # ─── UI ──────────────────────────────────────────────────────────────────

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # Top context bar
        layout.addWidget(self._build_context_bar())

        # Chat display + input splitter
        splitter = QSplitter(Qt.Orientation.Vertical)
        layout.addWidget(splitter, stretch=1)

        # Message display
        self._chat_display = QTextEdit()
        self._chat_display.setReadOnly(True)
        self._chat_display.setFont(QFont("monospace", 11))
        self._chat_display.setObjectName("chatDisplay")
        self._chat_display.setStyleSheet("""
            QTextEdit#chatDisplay {
                background-color: #FAFAFA;
                border: none;
                padding: 16px;
                line-height: 1.5;
            }
        """)
        splitter.addWidget(self._chat_display)

        # Input area
        input_widget = QWidget()
        input_layout = QVBoxLayout(input_widget)
        input_layout.setContentsMargins(12, 8, 12, 12)

        self._input = QPlainTextEdit()
        self._input.setPlaceholderText(
            "Ask about crops, pests, diseases, soil, or markets… "
            "(Ctrl+Enter to send)"
        )
        self._input.setMaximumHeight(120)
        self._input.setMinimumHeight(60)
        self._input.setFont(QFont("", 12))
        input_layout.addWidget(self._input)

        btn_row = QHBoxLayout()
        self._send_btn = QPushButton("Send (Ctrl+Enter)")
        self._send_btn.setEnabled(False)
        self._send_btn.setStyleSheet(
            "QPushButton { background: #2E7D32; color: white; padding: 8px 20px; "
            "border-radius: 6px; font-weight: bold; } "
            "QPushButton:hover { background: #388E3C; } "
            "QPushButton:disabled { background: #aaa; }"
        )
        self._send_btn.clicked.connect(self._on_send)

        self._stop_btn = QPushButton("Stop")
        self._stop_btn.setEnabled(False)
        self._stop_btn.setVisible(False)
        self._stop_btn.setStyleSheet(
            "QPushButton { background: #C62828; color: white; padding: 8px 20px; "
            "border-radius: 6px; } QPushButton:hover { background: #D32F2F; }"
        )
        self._stop_btn.clicked.connect(self._on_stop)

        self._clear_btn = QPushButton("Clear")
        self._clear_btn.clicked.connect(self.clear_chat)

        btn_row.addWidget(self._clear_btn)
        btn_row.addStretch()
        btn_row.addWidget(self._stop_btn)
        btn_row.addWidget(self._send_btn)
        input_layout.addLayout(btn_row)

        splitter.addWidget(input_widget)
        splitter.setSizes([500, 180])

    def _build_context_bar(self) -> QWidget:
        bar = QFrame()
        bar.setObjectName("contextBar")
        bar.setStyleSheet(
            "QFrame#contextBar { background: #E8F5E9; border-bottom: 1px solid #C8E6C9; }"
        )
        bar.setMaximumHeight(52)

        layout = QHBoxLayout(bar)
        layout.setContentsMargins(16, 6, 16, 6)

        layout.addWidget(QLabel("Region:"))
        self._region_combo = QComboBox()
        self._region_combo.addItems([
            "", "Kenya - Central", "Kenya - Rift Valley", "Kenya - Western",
            "Tanzania - Arusha", "Tanzania - Kilimanjaro", "Uganda - Central",
            "Uganda - Western", "Ethiopia - Oromia", "Rwanda", "Nigeria - Kano",
        ])
        layout.addWidget(self._region_combo)

        layout.addWidget(QLabel("Crop:"))
        self._crop_combo = QComboBox()
        self._crop_combo.addItems([
            "", "Maize", "Cassava", "Beans", "Sorghum", "Millet",
            "Tomato", "Kale (Sukuma Wiki)", "Tea", "Coffee", "Banana",
            "Groundnut", "Soybean", "Sweet Potato",
        ])
        layout.addWidget(self._crop_combo)

        layout.addWidget(QLabel("Season:"))
        self._season_combo = QComboBox()
        self._season_combo.addItems([
            "", "Long Rains (Mar–May)", "Short Rains (Oct–Dec)",
            "Dry Season", "Highland Season",
        ])
        layout.addWidget(self._season_combo)

        layout.addStretch()

        layout.addWidget(QLabel("Language:"))
        self._lang_btn = QPushButton("English")
        self._lang_btn.setCheckable(True)
        self._lang_btn.setStyleSheet(
            "QPushButton { padding: 4px 12px; border-radius: 4px; border: 1px solid #4CAF50; }"
            "QPushButton:checked { background: #2E7D32; color: white; }"
        )
        self._lang_btn.clicked.connect(self._toggle_language)
        layout.addWidget(self._lang_btn)

        return bar

    def _connect_signals(self) -> None:
        self._emitter.token.connect(self._on_token)
        self._emitter.done.connect(self._on_generation_done)
        self._emitter.error.connect(self._on_generation_error)

    # ─── Public API ──────────────────────────────────────────────────────────

    def set_model_ready(self, ready: bool) -> None:
        self._model_ready = ready
        self._send_btn.setEnabled(ready)
        if ready:
            self._append_system_message("✓ Model loaded and ready. How can I help you today?")

    def clear_chat(self) -> None:
        self._chat_display.clear()
        self._history.clear()
        self._append_system_message("Chat cleared. Ask me anything about your farm.")

    # ─── Message handling ─────────────────────────────────────────────────────

    def _on_send(self) -> None:
        text = self._input.toPlainText().strip()
        if not text or self._generating:
            return

        self._input.clear()
        self._history.append({"role": "user", "content": text})
        self._append_message("You", text, user=True)

        self._start_generation(text)

    def _on_stop(self) -> None:
        self.inference.cancel()
        self._generating = False
        self._set_generating_ui(False)
        self._append_system_message("[Generation stopped]")

    def _toggle_language(self) -> None:
        if self._lang_btn.isChecked():
            self._language = "sw"
            self._lang_btn.setText("Kiswahili")
        else:
            self._language = "en"
            self._lang_btn.setText("English")

    def _start_generation(self, user_text: str) -> None:
        self._generating = True
        self._set_generating_ui(True)

        # Retrieve RAG context
        region = self._region_combo.currentText() or None
        crop = self._crop_combo.currentText() or None
        season = self._season_combo.currentText() or None

        def _worker():
            # RAG retrieval
            rag_chunks = self.retriever.retrieve(
                query=user_text, top_k=3, language=self._language
            )

            # Build prompt
            prompt = self.prompt_engine.build_contextual_prompt(
                user_query=user_text,
                region=region,
                country=region.split(" - ")[0] if region and " - " in region else region,
                language=self._language,
                season=season,
                rag_context=rag_chunks,
            )

            # Add crop context to prompt if set
            if crop:
                prompt = prompt.replace(
                    "\nUser:", f"\n[Active crop: {crop}]\nUser:", 1
                )

            # Stream generation
            try:
                for token in self.inference.generate_stream(prompt):
                    self._emitter.token.emit(token)
                self._emitter.done.emit(rag_chunks)
            except Exception as exc:
                self._emitter.error.emit(str(exc))

        thread = threading.Thread(target=_worker, daemon=True)
        thread.start()

        # Add assistant placeholder
        self._append_message("Maathai AI", "", user=False)

    def _on_token(self, token: str) -> None:
        cursor = self._chat_display.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        cursor.insertText(token)
        self._chat_display.setTextCursor(cursor)
        self._chat_display.ensureCursorVisible()

    def _on_generation_done(self, rag_chunks: list) -> None:
        self._generating = False
        self._set_generating_ui(False)

        # Save to history
        response_text = self._get_last_assistant_text()
        self._history.append({"role": "assistant", "content": response_text})

        # Show RAG sources
        if rag_chunks:
            sources = "\n".join(
                f"  • {c['source']}" for c in rag_chunks[:3]
            )
            self._append_system_message(f"Knowledge sources:\n{sources}")

    def _on_generation_error(self, error: str) -> None:
        self._generating = False
        self._set_generating_ui(False)
        self._append_system_message(f"⚠ Error: {error}")
        logger.error("Generation error: %s", error)

    def _get_last_assistant_text(self) -> str:
        text = self._chat_display.toPlainText()
        marker = "\nMaathai AI:\n"
        idx = text.rfind(marker)
        if idx >= 0:
            return text[idx + len(marker):].strip()
        return ""

    def _set_generating_ui(self, generating: bool) -> None:
        self._send_btn.setEnabled(not generating and self._model_ready)
        self._send_btn.setVisible(not generating)
        self._stop_btn.setEnabled(generating)
        self._stop_btn.setVisible(generating)
        self._input.setEnabled(not generating)

    def _append_message(self, role: str, content: str, user: bool = True) -> None:
        cursor = self._chat_display.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)

        ts = datetime.now().strftime("%H:%M")
        separator = "─" * 60
        if user:
            cursor.insertText(f"\n{separator}\n{role}  [{ts}]\n{content}\n\n")
        else:
            cursor.insertText(f"\n{role}  [{ts}]\n")

        self._chat_display.setTextCursor(cursor)
        self._chat_display.ensureCursorVisible()

    def _append_system_message(self, message: str) -> None:
        cursor = self._chat_display.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        cursor.insertText(f"\n[{message}]\n")
        self._chat_display.setTextCursor(cursor)
        self._chat_display.ensureCursorVisible()

    def keyPressEvent(self, event) -> None:
        if (
            event.key() == Qt.Key.Key_Return
            and event.modifiers() == Qt.KeyboardModifier.ControlModifier
        ):
            self._on_send()
        else:
            super().keyPressEvent(event)
