"""
Maathai Desktop — Main Application Window (PyQt6)

Single-window layout with sidebar navigation and three panels:
  - Chat: streaming agriculture Q&A (English + Swahili)
  - Knowledge Browser: offline knowledge base
  - Benchmark: live RAM / TPS / CPU temp display

Design is intentionally practical — suitable for an extension officer's office
computer, not a consumer app. Clear, readable, keyboard-friendly.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Optional

from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject, QThread
from PyQt6.QtGui import QAction, QKeySequence, QFont
from PyQt6.QtWidgets import (
    QApplication,
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QSplitter,
    QStackedWidget,
    QStatusBar,
    QToolBar,
    QVBoxLayout,
    QWidget,
)

from src.config import APP_NAME, APP_VERSION, MODEL_DIR, RAM_WARN_THRESHOLD_MB, CPU_TEMP_WARN_C
from src.llm.inference import LlamaInference
from src.rag.retriever import Retriever
from src.llm.prompt_engine import PromptEngine
from src.ui.chat_view import ChatView
from src.ui.knowledge_view import KnowledgeView
from src.ui.benchmark_view import BenchmarkView

logger = logging.getLogger(__name__)


class ModelLoader(QObject):
    """Background thread worker to load the GGUF model without blocking the UI."""

    finished = pyqtSignal(bool, str)  # success, message

    def __init__(self, inference: LlamaInference, model_path: str) -> None:
        super().__init__()
        self._inference = inference
        self._model_path = model_path

    def run(self) -> None:
        success = self._inference.load_model(self._model_path)
        msg = "Model loaded successfully" if success else "Failed to load model"
        self.finished.emit(success, msg)


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()

        self.inference = LlamaInference()
        self.retriever = Retriever()
        self.prompt_engine = PromptEngine()

        self._setup_ui()
        self._setup_menu()
        self._setup_status_bar()
        self._init_rag()

        # Auto-load default model if present
        QTimer.singleShot(500, self._auto_load_model)

    # ─── UI setup ────────────────────────────────────────────────────────────

    def _setup_ui(self) -> None:
        self.setWindowTitle(f"{APP_NAME} v{APP_VERSION}")
        self.setMinimumSize(1000, 650)
        self.resize(1280, 780)

        central = QWidget()
        self.setCentralWidget(central)
        layout = QHBoxLayout(central)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # Left navigation sidebar
        sidebar = self._build_sidebar()
        layout.addWidget(sidebar)

        # Vertical separator
        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.VLine)
        sep.setFrameShadow(QFrame.Shadow.Sunken)
        layout.addWidget(sep)

        # Main content stack
        self._stack = QStackedWidget()
        layout.addWidget(self._stack, stretch=1)

        # Register panels
        self.chat_view = ChatView(self.inference, self.retriever, self.prompt_engine)
        self.knowledge_view = KnowledgeView(self.retriever)
        self.benchmark_view = BenchmarkView(self.inference)

        self._stack.addWidget(self.chat_view)       # index 0
        self._stack.addWidget(self.knowledge_view)  # index 1
        self._stack.addWidget(self.benchmark_view)  # index 2

    def _build_sidebar(self) -> QWidget:
        sidebar = QWidget()
        sidebar.setFixedWidth(64)
        sidebar.setObjectName("sidebar")
        sidebar.setStyleSheet("""
            QWidget#sidebar {
                background-color: #1B5E20;
                color: white;
            }
            QPushButton {
                background: transparent;
                color: white;
                border: none;
                padding: 8px 4px;
                font-size: 11px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #2E7D32;
            }
            QPushButton:checked {
                background-color: #388E3C;
                font-weight: bold;
            }
        """)
        layout = QVBoxLayout(sidebar)
        layout.setContentsMargins(4, 12, 4, 12)
        layout.setSpacing(4)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        # Logo / brand
        logo = QLabel("🌱")
        logo.setAlignment(Qt.AlignmentFlag.AlignCenter)
        logo.setFont(QFont("", 22))
        layout.addWidget(logo)

        brand = QLabel("Maathai")
        brand.setAlignment(Qt.AlignmentFlag.AlignCenter)
        brand.setStyleSheet("color: white; font-size: 9px; font-weight: bold;")
        layout.addWidget(brand)
        layout.addSpacing(12)

        # Navigation buttons
        self._nav_buttons: list[QPushButton] = []

        for icon, label, idx in [
            ("💬", "Chat", 0),
            ("📚", "Knowledge", 1),
            ("📊", "Benchmark", 2),
        ]:
            btn = QPushButton(f"{icon}\n{label}")
            btn.setCheckable(True)
            btn.setFixedHeight(56)
            btn.clicked.connect(lambda _, i=idx: self._switch_panel(i))
            self._nav_buttons.append(btn)
            layout.addWidget(btn)

        self._nav_buttons[0].setChecked(True)

        layout.addStretch()

        # Model status indicator
        self._model_status = QLabel("●")
        self._model_status.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._model_status.setStyleSheet("color: #aaa; font-size: 18px;")
        self._model_status.setToolTip("Model not loaded")
        layout.addWidget(self._model_status)

        return sidebar

    def _switch_panel(self, index: int) -> None:
        self._stack.setCurrentIndex(index)
        for i, btn in enumerate(self._nav_buttons):
            btn.setChecked(i == index)

    def _setup_menu(self) -> None:
        menu = self.menuBar()

        file_menu = menu.addMenu("&File")
        load_action = QAction("&Load Model…", self)
        load_action.setShortcut(QKeySequence("Ctrl+O"))
        load_action.triggered.connect(self._pick_and_load_model)
        file_menu.addAction(load_action)

        new_chat = QAction("&New Chat", self)
        new_chat.setShortcut(QKeySequence("Ctrl+N"))
        new_chat.triggered.connect(lambda: self.chat_view.clear_chat())
        file_menu.addAction(new_chat)

        file_menu.addSeparator()
        file_menu.addAction("&Quit", QApplication.quit, "Ctrl+Q")

        help_menu = menu.addMenu("&Help")
        about_action = QAction("&About Maathai", self)
        about_action.triggered.connect(self._show_about)
        help_menu.addAction(about_action)

    def _setup_status_bar(self) -> None:
        self._status_bar = self.statusBar()

        self._model_label = QLabel("No model loaded")
        self._status_bar.addPermanentWidget(self._model_label)

        self._ram_label = QLabel("RAM: —")
        self._status_bar.addPermanentWidget(self._ram_label)

        self._tps_label = QLabel("TPS: —")
        self._status_bar.addPermanentWidget(self._tps_label)

        # Update RAM/CPU stats every 2 seconds
        self._stats_timer = QTimer(self)
        self._stats_timer.timeout.connect(self._update_stats)
        self._stats_timer.start(2000)

    def _update_stats(self) -> None:
        try:
            import psutil  # noqa: PLC0415
            proc = psutil.Process()
            ram_mb = proc.memory_info().rss / 1024 / 1024
            label = f"RAM: {ram_mb:.0f} MB"
            if ram_mb > RAM_WARN_THRESHOLD_MB:
                label = f"⚠ RAM: {ram_mb:.0f} MB"
                self._ram_label.setStyleSheet("color: red; font-weight: bold;")
            else:
                self._ram_label.setStyleSheet("")
            self._ram_label.setText(label)
        except Exception:
            pass

    # ─── Model loading ───────────────────────────────────────────────────────

    def _init_rag(self) -> None:
        def _load():
            ok = self.retriever.initialize()
            if not ok:
                logger.info("Building knowledge base index...")
                from src.rag.build_index import build_index  # noqa: PLC0415
                build_index()
                self.retriever.initialize()

        thread = threading.Thread(target=_load, daemon=True)
        thread.start()

    def _auto_load_model(self) -> None:
        gguf_files = sorted(MODEL_DIR.glob("*.gguf"))
        if not gguf_files:
            self._status_bar.showMessage(
                "No model found. Run: bash download_model.sh", 8000
            )
            return
        model_path = str(gguf_files[0])
        self._load_model_async(model_path)

    def _pick_and_load_model(self) -> None:
        from PyQt6.QtWidgets import QFileDialog  # noqa: PLC0415

        path, _ = QFileDialog.getOpenFileName(
            self, "Select GGUF Model", str(MODEL_DIR), "GGUF Models (*.gguf)"
        )
        if path:
            self._load_model_async(path)

    def _load_model_async(self, model_path: str) -> None:
        self._model_label.setText(f"Loading {Path(model_path).name}…")
        self._model_status.setStyleSheet("color: orange; font-size: 18px;")
        self._model_status.setToolTip("Loading model...")

        self._loader_thread = QThread()
        self._loader = ModelLoader(self.inference, model_path)
        self._loader.moveToThread(self._loader_thread)
        self._loader_thread.started.connect(self._loader.run)
        self._loader.finished.connect(self._on_model_loaded)
        self._loader.finished.connect(self._loader_thread.quit)
        self._loader_thread.start()

    def _on_model_loaded(self, success: bool, message: str) -> None:
        if success:
            model_name = Path(self.inference._model_path or "").name
            self._model_label.setText(f"✓ {model_name}")
            self._model_status.setStyleSheet("color: #69F0AE; font-size: 18px;")
            self._model_status.setToolTip(f"Model ready: {model_name}")
            self.chat_view.set_model_ready(True)
            self._status_bar.showMessage("Model loaded. Ready to chat.", 3000)
        else:
            self._model_label.setText("Model error")
            self._model_status.setStyleSheet("color: red; font-size: 18px;")
            self._model_status.setToolTip(f"Error: {message}")
            QMessageBox.critical(self, "Model Load Error", message)

    # ─── Misc ─────────────────────────────────────────────────────────────────

    def _show_about(self) -> None:
        QMessageBox.about(
            self,
            f"About {APP_NAME}",
            f"<b>{APP_NAME}</b> v{APP_VERSION}<br><br>"
            "Offline AI agriculture advisor for smallholder farmers in Africa.<br><br>"
            "<b>ADTC 2026</b> — Africa Deep Tech Challenge<br>"
            "Domain: Agriculture · Language: English + Swahili<br><br>"
            "Model: Qwen2.5-3B-Instruct Q4_K_M<br>"
            "Runtime: llama.cpp (llama-cpp-python)<br>"
            "RAG: ChromaDB + sentence-transformers<br><br>"
            "Open source · usemaathai.com",
        )

    def closeEvent(self, event) -> None:
        self._stats_timer.stop()
        self.inference.release()
        super().closeEvent(event)
