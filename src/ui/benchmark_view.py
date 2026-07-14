"""
Maathai Desktop — Benchmark/Monitor View (PyQt6)

Live display of:
- Peak RAM usage (vs 7 GB ADTC limit)
- CPU temperature (vs 85°C ADTC penalty threshold)
- Tokens per second (for Sperf scoring)
- Process stats

Useful for demo video recording and self-monitoring before submission.
Corresponds to the ADTC profiler's telemetry metrics.
"""

from __future__ import annotations

import logging
import time
from collections import deque
from typing import Deque

from PyQt6.QtCore import QTimer
from PyQt6.QtWidgets import (
    QGroupBox,
    QLabel,
    QProgressBar,
    QVBoxLayout,
    QWidget,
    QGridLayout,
)

from src.llm.inference import LlamaInference
from src.config import CPU_TEMP_WARN_C, RAM_WARN_THRESHOLD_MB

logger = logging.getLogger(__name__)

RAM_LIMIT_MB = 7 * 1024  # 7 GB competition limit


class BenchmarkView(QWidget):
    def __init__(self, inference: LlamaInference) -> None:
        super().__init__()
        self.inference = inference
        self._tps_history: Deque[float] = deque(maxlen=30)
        self._peak_ram_mb = 0.0

        self._setup_ui()

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._update)
        self._timer.start(2000)

    def _setup_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 24, 24, 24)
        layout.setSpacing(16)

        title = QLabel("Live Benchmark Monitor")
        title.setStyleSheet("font-size: 18px; font-weight: bold;")
        layout.addWidget(title)

        subtitle = QLabel(
            "ADTC 2026 competition metrics — updated every 2 seconds"
        )
        subtitle.setStyleSheet("color: grey;")
        layout.addWidget(subtitle)

        # RAM group
        ram_group = QGroupBox("Memory (RAM)")
        ram_layout = QVBoxLayout(ram_group)

        self._ram_label = QLabel("Current: — MB")
        ram_layout.addWidget(self._ram_label)

        self._peak_label = QLabel("Peak: — MB")
        ram_layout.addWidget(self._peak_label)

        self._ram_bar = QProgressBar()
        self._ram_bar.setMaximum(RAM_LIMIT_MB)
        self._ram_bar.setFormat("%v MB / 7168 MB limit")
        ram_layout.addWidget(self._ram_bar)

        self._seff_label = QLabel("Seff score: —")
        self._seff_label.setStyleSheet("font-weight: bold; color: #2E7D32;")
        ram_layout.addWidget(self._seff_label)

        layout.addWidget(ram_group)

        # TPS group
        tps_group = QGroupBox("Inference Speed")
        tps_layout = QGridLayout(tps_group)

        tps_layout.addWidget(QLabel("Last TPS:"), 0, 0)
        self._tps_label = QLabel("—")
        self._tps_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #1565C0;")
        tps_layout.addWidget(self._tps_label, 0, 1)

        tps_layout.addWidget(QLabel("Sperf (vs 15 TPS ref):"), 1, 0)
        self._sperf_label = QLabel("—")
        self._sperf_label.setStyleSheet("font-weight: bold; color: #2E7D32;")
        tps_layout.addWidget(self._sperf_label, 1, 1)

        layout.addWidget(tps_group)

        # CPU/Thermal group
        thermal_group = QGroupBox("CPU & Thermal")
        thermal_layout = QGridLayout(thermal_group)

        thermal_layout.addWidget(QLabel("CPU Usage:"), 0, 0)
        self._cpu_label = QLabel("—%")
        thermal_layout.addWidget(self._cpu_label, 0, 1)

        thermal_layout.addWidget(QLabel("CPU Temperature:"), 1, 0)
        self._temp_label = QLabel("— °C")
        thermal_layout.addWidget(self._temp_label, 1, 1)

        thermal_layout.addWidget(QLabel("Thermal penalty risk:"), 2, 0)
        self._penalty_label = QLabel("None detected")
        self._penalty_label.setStyleSheet("color: green;")
        thermal_layout.addWidget(self._penalty_label, 2, 1)

        layout.addWidget(thermal_group)

        # Scoring estimate
        score_group = QGroupBox("Estimated Competition Score")
        score_layout = QVBoxLayout(score_group)
        self._score_label = QLabel("Stotal = (collecting data…)")
        self._score_label.setStyleSheet("font-size: 14px; font-weight: bold;")
        score_layout.addWidget(self._score_label)
        score_note = QLabel(
            "Formula: 0.50×Sacc + 0.30×Sperf + 0.20×Seff − Pthermal\n"
            "Sacc (accuracy) is judged manually — not shown here.\n"
            "African Alpha Bonus: +15% if african_alpha_claim=true"
        )
        score_note.setStyleSheet("color: grey; font-size: 11px;")
        score_layout.addWidget(score_note)
        layout.addWidget(score_group)

        layout.addStretch()

    def _update(self) -> None:
        try:
            import psutil  # noqa: PLC0415

            proc = psutil.Process()

            # RAM
            ram_mb = proc.memory_info().rss / 1024 / 1024
            if ram_mb > self._peak_ram_mb:
                self._peak_ram_mb = ram_mb

            self._ram_label.setText(f"Current: {ram_mb:.0f} MB")
            self._peak_label.setText(f"Peak: {self._peak_ram_mb:.0f} MB")
            self._ram_bar.setValue(int(ram_mb))

            # Color RAM bar
            if ram_mb > RAM_WARN_THRESHOLD_MB:
                self._ram_bar.setStyleSheet("QProgressBar::chunk { background: red; }")
            elif ram_mb > RAM_LIMIT_MB * 0.7:
                self._ram_bar.setStyleSheet("QProgressBar::chunk { background: orange; }")
            else:
                self._ram_bar.setStyleSheet("QProgressBar::chunk { background: #4CAF50; }")

            seff = max(0, (7168 - self._peak_ram_mb) / 7168 * 100)
            self._seff_label.setText(f"Seff score: {seff:.1f} / 100")

            # CPU
            cpu_pct = proc.cpu_percent(interval=None)
            self._cpu_label.setText(f"{cpu_pct:.0f}%")

            # Temperature (Linux: psutil.sensors_temperatures)
            try:
                temps = psutil.sensors_temperatures()
                if temps:
                    all_temps = [
                        t.current
                        for sensor_list in temps.values()
                        for t in sensor_list
                        if t.current > 0
                    ]
                    if all_temps:
                        max_temp = max(all_temps)
                        self._temp_label.setText(f"{max_temp:.0f} °C")
                        if max_temp > CPU_TEMP_WARN_C:
                            self._temp_label.setStyleSheet("color: red; font-weight: bold;")
                            self._penalty_label.setText(f"⚠ {max_temp:.0f}°C > {CPU_TEMP_WARN_C}°C — Penalty risk!")
                            self._penalty_label.setStyleSheet("color: red; font-weight: bold;")
                        elif max_temp > CPU_TEMP_WARN_C - 5:
                            self._temp_label.setStyleSheet("color: orange;")
                            self._penalty_label.setText("Approaching thermal limit")
                            self._penalty_label.setStyleSheet("color: orange;")
                        else:
                            self._temp_label.setStyleSheet("color: green;")
                            self._penalty_label.setText("None detected ✓")
                            self._penalty_label.setStyleSheet("color: green;")
            except (AttributeError, Exception):
                self._temp_label.setText("N/A (Linux only)")

            # Score estimate (Sperf uses TPS_REFERENCE = 15.0 from ADTC profiler)
            if self._tps_history:
                avg_tps = sum(self._tps_history) / len(self._tps_history)
                sperf = min(avg_tps / 15.0, 1.0) * 100
                self._tps_label.setText(f"{avg_tps:.1f} tok/s")
                self._sperf_label.setText(f"Sperf score: {sperf:.1f} / 100")

                stotal_estimate = 0.30 * sperf + 0.20 * seff
                self._score_label.setText(
                    f"Stotal ≈ 0.50×Sacc + 0.30×{sperf:.0f} + 0.20×{seff:.0f} = "
                    f"(0.50×Sacc + {0.30*sperf + 0.20*seff:.0f})"
                )
        except ImportError:
            self._ram_label.setText("psutil not installed")
        except Exception as exc:
            logger.debug("Benchmark update error: %s", exc)

    def record_tps(self, tps: float) -> None:
        """Called by inference layer to record tokens-per-second."""
        self._tps_history.append(tps)
