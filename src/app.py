"""
Maathai Desktop — Application Entry Point

Run: python src/app.py
OR:  python -m src.app
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

# Ensure repo root is on path when run as script
sys.path.insert(0, str(Path(__file__).parent.parent))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)

logger = logging.getLogger(__name__)


def main() -> int:
    try:
        from PyQt6.QtWidgets import QApplication  # noqa: PLC0415
        from PyQt6.QtGui import QIcon  # noqa: PLC0415
    except ImportError:
        print("PyQt6 is not installed. Run: pip install -r requirements.txt")
        return 1

    app = QApplication(sys.argv)
    app.setApplicationName("Maathai Desktop")
    app.setOrganizationName("Maathai")
    app.setApplicationVersion("1.0.0")

    # Apply base stylesheet
    app.setStyleSheet("""
        QMainWindow, QWidget {
            font-family: "Inter", "Segoe UI", sans-serif;
            font-size: 13px;
        }
        QToolTip {
            background-color: #333;
            color: white;
            border: 1px solid #555;
            padding: 4px;
        }
    """)

    from src.ui.main_window import MainWindow  # noqa: PLC0415

    window = MainWindow()
    window.show()

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
