import sys
import json
import os
import copy
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QComboBox, QLabel, QLineEdit, QPushButton,
    QScrollArea, QGroupBox, QMessageBox, QCheckBox, QTabWidget,
    QPlainTextEdit, QFrame, QToolTip,
)
from PySide6.QtCore import Qt, QPoint, QRect
from PySide6.QtGui import QIntValidator, QDoubleValidator

SCRIPT_DIR    = os.path.dirname(os.path.abspath(__file__))
UIMPIT_CONFIG = os.path.join(SCRIPT_DIR, "Resources", "Server", "UIMPIT", "config", "config.json")
UIMPI_CONFIG  = os.path.join(SCRIPT_DIR, "Resources", "Server", "UIMPI",  "config.json")
LANG_DIR      = os.path.join(SCRIPT_DIR, "Resources", "Server", "UIMPIT", "lang")

SUPPORTED_LANGS = ("en", "he", "ar", "de", "it", "fr", "es", "ru")
RTL_LANGS       = {"he", "ar"}

# ---------------------------------------------------------------------------
# Load translations from lang/editor_{code}.json
# ---------------------------------------------------------------------------

def _load_translations() -> dict[str, dict]:
    result: dict[str, dict] = {}
    en_path = os.path.join(LANG_DIR, "editor_en.json")
    try:
        with open(en_path, encoding="utf-8") as f:
            result["en"] = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        sys.exit(f"[config_editor] Fatal: cannot load editor_en.json — {e}")
    for code in SUPPORTED_LANGS:
        if code == "en":
            continue
        path = os.path.join(LANG_DIR, f"editor_{code}.json")
        try:
            with open(path, encoding="utf-8") as f:
                result[code] = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            result[code] = {}
    return result

EDITOR_TRANSLATIONS: dict[str, dict] = _load_translations()
LANG_MAP: dict[str, str] = {
    v.get("lang_name", code): code
    for code, v in EDITOR_TRANSLATIONS.items()
    if v.get("lang_name")
}

# ---------------------------------------------------------------------------
# Field definitions
# ---------------------------------------------------------------------------

FIELDS = [
    ("features", "roleplay_enabled",               "bool"),
    ("features", "money_per_minute_enabled",       "bool"),
    ("features", "cool_message_enabled",           "bool"),
    ("features", "speeding_bonus_enabled",         "bool"),
    ("features", "zigzag_bonus_enabled",           "bool"),
    ("features", "police_features_enabled",        "bool"),
    ("features", "spawn_teleport_enabled",         "bool"),
    ("features", "markers_enabled",                "bool"),
    ("features", "ranks_enabled",                  "bool"),
    ("features", "playerlist_custom_data_enabled", "bool"),
    ("general",  "autosave_interval_ms",           "int"),
    ("money",    "starting_money",                 "int"),
    ("money",    "money_per_minute_amount",        "int"),
    ("money",    "money_per_minute_interval_ms",   "int"),
    ("money",    "cool_message_interval_ms",       "int"),
    ("civilian", "speeding_limit_kmh",                "int"),
    ("civilian", "speeding_bonus_per_second",         "int"),
    ("civilian", "speeding_final_bonus_amount",       "int"),
    ("civilian", "speeding_bonus_duration_ms",        "int"),
    ("civilian", "speeding_cooldown_ms",              "int"),
    ("civilian", "speeding_allowed_repairs",          "int"),
    ("civilian", "min_speed_kmh_for_zigzag",          "int"),
    ("civilian", "zigzag_min_turns",                  "int"),
    ("civilian", "zigzag_min_angle_degrees",          "int"),
    ("civilian", "zigzag_max_turn_interval_seconds",  "float"),
    ("civilian", "zigzag_prorated_bonus",             "int"),
    ("civilian", "zigzag_final_bonus_amount",         "int"),
    ("civilian", "zigzag_bonus_duration_ms",          "int"),
    ("civilian", "zigzag_cooldown_ms",                "int"),
    ("civilian", "zigzag_allowed_repairs",            "int"),
    ("civilian", "combo_allowed_repairs",             "int"),
    ("civilian", "wanted_fail_penalty",               "int"),
    ("civilian", "max_speed_for_repair_kmh",          "int"),
    ("police",   "police_proximity_range_m",  "int"),
    ("police",   "busted_range_m",            "int"),
    ("police",   "busted_stop_time_ms",       "int"),
    ("police",   "busted_speed_limit_kmh",    "int"),
    ("police",   "police_bonus_per_second",   "int"),
    ("police",   "bust_bonus_amount",         "int"),
    ("police",   "police_allowed_repairs",    "int"),
    ("police",   "repair_proximity_limit_m",  "int"),
    ("system",   "repair_reset_time_seconds",       "int"),
    ("system",   "chase_accumulator_chunk_seconds", "int"),
    ("system",   "teleport_cooldown_seconds",       "int"),
    ("system",   "repair_approval_window_seconds",  "int"),
    ("system",   "repair_proximity_limit_m",        "int"),
    ("markers",       "spawn_delay_ms",       "int"),
    ("markers",       "max_markers",          "int"),
    ("markers",       "marker_type",          "int"),
    ("markers",       "marker_scale",         "int"),
    ("markers",       "marker_reward_amount", "int"),
    ("marker_color",  "r", "int"),
    ("marker_color",  "g", "int"),
    ("marker_color",  "b", "int"),
    ("marker_color",  "a", "int"),
    ("air_polluter",  "min_players",    "int"),
    ("air_polluter",  "cooldown_secs",  "int"),
    ("air_polluter",  "hover_radius_m", "int"),
    ("air_polluter",  "touch_radius_m", "int"),
    ("timers", "welcome_checker_ms",       "int"),
    ("timers", "fast_marker_check_ms",     "int"),
    ("timers", "combined_checker_ms",      "int"),
    ("timers", "role_checker_ms",          "int"),
    ("timers", "zigzag_checker_ms",        "int"),
    ("timers", "money_sync_ms",            "int"),
    ("timers", "rank_save_ms",             "int"),
    ("timers", "rank_ui_update_ms",        "int"),
    ("timers", "police_wanted_update_ms",  "int"),
    ("timers", "editing_position_sync_ms", "int"),
    # ── Performance Limiter (UIMPI) ──────────────────────────────────────────
    ("uimpi", "max_performance_rating", "int"),
    ("uimpi", "display_offset",         "int"),
    ("uimpi", "vote_enabled",           "bool"),
    ("uimpi", "vote_duration",          "int"),
]

FALLBACK_DEFAULTS = {
    "features": {
        "roleplay_enabled": True, "money_per_minute_enabled": True,
        "cool_message_enabled": True, "speeding_bonus_enabled": True,
        "zigzag_bonus_enabled": True, "police_features_enabled": True,
        "spawn_teleport_enabled": True, "markers_enabled": True,
        "ranks_enabled": True, "playerlist_custom_data_enabled": True,
    },
    "general":  {"autosave_interval_ms": 120000},
    "money":    {"starting_money": 50000, "money_per_minute_amount": 75,
                 "money_per_minute_interval_ms": 180000, "cool_message_interval_ms": 200000},
    "civilian": {
        "speeding_limit_kmh": 150, "speeding_bonus_per_second": 4,
        "speeding_bonus_duration_ms": 240000, "speeding_cooldown_ms": 1,
        "speeding_final_bonus_amount": 900, "speeding_allowed_repairs": 0,
        "min_speed_kmh_for_zigzag": 30, "zigzag_min_turns": 4,
        "zigzag_min_angle_degrees": 12, "zigzag_max_turn_interval_seconds": 2.0,
        "zigzag_prorated_bonus": 7, "zigzag_final_bonus_amount": 1500,
        "zigzag_bonus_duration_ms": 420000, "zigzag_cooldown_ms": 1,
        "zigzag_allowed_repairs": 0, "combo_allowed_repairs": 1,
        "wanted_fail_penalty": 750, "max_speed_for_repair_kmh": 5,
    },
    "police": {
        "police_proximity_range_m": 150, "busted_range_m": 25,
        "busted_stop_time_ms": 7000, "busted_speed_limit_kmh": 5,
        "police_bonus_per_second": 8, "bust_bonus_amount": 3000,
        "police_allowed_repairs": 1, "repair_proximity_limit_m": 50,
    },
    "system": {
        "repair_reset_time_seconds": 300, "chase_accumulator_chunk_seconds": 10,
        "teleport_cooldown_seconds": 5, "repair_approval_window_seconds": 2,
        "repair_proximity_limit_m": 50,
    },
    "markers": {
        "spawn_delay_ms": 60000, "max_markers": 3, "marker_type": 1,
        "marker_scale": 10, "marker_reward_amount": 200,
        "marker_color": {"r": 0, "g": 255, "b": 255, "a": 200},
    },
    "air_polluter": {"min_players": 4, "cooldown_secs": 21600,
                     "hover_radius_m": 2, "touch_radius_m": 2},
    "timers": {
        "welcome_checker_ms": 500, "fast_marker_check_ms": 150,
        "combined_checker_ms": 1000, "role_checker_ms": 5000,
        "zigzag_checker_ms": 500, "money_sync_ms": 10000,
        "rank_save_ms": 60000, "rank_ui_update_ms": 2000,
        "police_wanted_update_ms": 1000, "editing_position_sync_ms": 200,
    },
    "admins":     ["BeamMP_name_of_the_player"],
    "moderators": ["BeamMP_name_of_the_player"],
}

UIMPI_FALLBACK_DEFAULTS = {
    "max_performance_rating": 122,
    "display_offset":         2,
    "admins":                 ["Player_name"],
    "vote_enabled":           False,
    "vote_duration":          20,
    "vote_options":           [80, 100, 120, 150, 200, 250],
}

# ---------------------------------------------------------------------------
# Value-type metadata  →  (badge_text, text_color, bg_color, bar_color)
# ---------------------------------------------------------------------------

_TYPE_META: dict[str, tuple[str, str, str, str]] = {
    "time":  ("⏱ TIME",  "#1d6fa4", "#dbeafe", "#3b82f6"),
    "money": ("$ MONEY", "#166534", "#dcfce7", "#22c55e"),
    "dist":  ("↔ DIST",  "#92400e", "#fef3c7", "#f59e0b"),
    "speed": ("⚡ SPEED", "#991b1b", "#fee2e2", "#ef4444"),
    "count": ("# VALUE", "#4c1d95", "#ede9fe", "#8b5cf6"),
}

def _field_type(key: str) -> str:
    if key.endswith(("_ms", "_seconds", "_secs")):
        return "time"
    if any(s in key for s in ("money", "bonus", "amount", "reward", "penalty")):
        return "money"
    if "_kmh" in key:
        return "speed"
    if key.endswith("_m") or any(s in key for s in ("_range_", "_radius_", "_proximity_", "_limit_m")):
        return "dist"
    return "count"

def _make_badge(type_key: str) -> QLabel:
    text, fg, bg, _ = _TYPE_META.get(type_key, _TYPE_META["count"])
    badge = QLabel(text)
    badge.setStyleSheet(
        f"color:{fg}; background:{bg}; border-radius:3px; padding:1px 6px;"
        f"font-size:9px; font-weight:800; border:1px solid {fg}70;"
    )
    badge.setFixedHeight(16)
    return badge

# ---------------------------------------------------------------------------
# Icons
# ---------------------------------------------------------------------------

GROUP_ICONS: dict[str, str] = {
    "features_title": "⚙️", "general_title": "🔧", "money_title": "💰",
    "civilian_title": "🚗", "police_title": "🚔", "system_title": "🔩",
    "markers_title": "📍", "marker_color_title": "🎨",
    "air_polluter_title": "💨", "admins_title": "👤",
    "moderators_title": "🛡️", "timers_title": "⏱️",
    # UIMPI
    "uimpi_general_title": "⚡",
    "uimpi_vote_title":    "🗳️",
    "uimpi_admins_title":  "👤",
}
TAB_ICONS: dict[str, str] = {
    "tab_features": "⚙️", "tab_economy": "💰", "tab_civilian": "🚗",
    "tab_police": "🚔", "tab_markers": "📍", "tab_air_polluter": "💨",
    "tab_admins": "👤", "tab_timers": "⏱️",
    "tab_uimpi":  "⚡",
}
SECTION_ICONS: dict[str, str] = {
    "section_speeding": "🚀", "section_zigzag": "↔️", "section_misc": "⚙️",
}

# ---------------------------------------------------------------------------
# Time hint helper
# ---------------------------------------------------------------------------

def fmt_time(text: str, key: str) -> str:
    try:
        val = float(text)
    except (ValueError, TypeError):
        return ""
    if val <= 0:
        return ""
    if key.endswith("_ms"):
        if val < 1000:
            return f"{val:.0f} ms"
        secs = val / 1000.0
    elif key.endswith("_seconds") or key.endswith("_secs"):
        secs = val
    else:
        return ""
    if secs < 1:
        return f"{secs * 1000:.0f} ms"
    if secs < 60:
        return f"≈ {secs:.0f}s"
    if secs < 3600:
        m, s = divmod(int(secs), 60)
        return f"≈ {m}m {s}s" if s else f"≈ {m}m"
    h, rem = divmod(int(secs), 3600)
    m = rem // 60
    return f"≈ {h}h {m}m" if m else f"≈ {h}h"

def is_time_key(key: str) -> bool:
    return key.endswith("_ms") or key.endswith("_seconds") or key.endswith("_secs")

# ---------------------------------------------------------------------------
# Stylesheet
# ---------------------------------------------------------------------------

STYLESHEET = """
/* ── Tooltip ───────────────────────────────────────────────────────────────── */
QToolTip {
    background: #1e293b; color: #f1f5f9;
    border: 1px solid #3b82f6; border-radius: 6px;
    padding: 7px 10px; font-size: 12px;
}

/* ── Base ─────────────────────────────────────────────────────────────────── */
QMainWindow { background: #f1f5f9; }
QWidget     { color: #1e293b; font-family: 'Segoe UI', Arial, sans-serif;
              font-size: 12px; background: transparent; }
#ScrollContent { background: #d1d9e6; }

/* ── Tabs ──────────────────────────────────────────────────────────────────── */
QTabWidget::pane {
    border: 1px solid #cbd5e1; border-radius: 10px;
    background: #d1d9e6; top: -1px;
}
QTabBar {
    alignment: center;
}
QTabBar::tab {
    background: #e2e8f0; color: #64748b;
    padding: 7px 16px; border-radius: 8px 8px 0 0;
    margin-right: 2px; font-weight: 600; font-size: 11px;
}
QTabBar::tab:selected  { background: #dc2626; color: #fff; }
QTabBar::tab:hover:!selected { background: #cbd5e1; color: #334155; }

/* ── Group boxes ───────────────────────────────────────────────────────────── */
QGroupBox {
    background: #ffffff; border: 1px solid #cbd5e1;
    border-radius: 10px; margin-top: 18px;
    padding: 10px 8px 8px 8px;
    font-size: 11px; font-weight: 700; color: #2563eb;
}
QGroupBox::title {
    subcontrol-origin: margin; subcontrol-position: top left;
    left: 12px; padding: 0 8px;
    background: #f1f5f9; border-radius: 4px;
}

/* ── Field cards ───────────────────────────────────────────────────────────── */
#FieldCard {
    background: #f8fafc; border: 1px solid #e2e8f0;
    border-radius: 8px;
}

/* ── Section dividers ──────────────────────────────────────────────────────── */
#SectionLabel {
    font-size: 11px; font-weight: 700; color: #2563eb;
    padding: 8px 2px 4px 2px;
    border-bottom: 1px solid #e2e8f0;
}

/* ── Labels ────────────────────────────────────────────────────────────────── */
#FieldLabel { font-size: 11px; color: #475569; }
#TimeHint   {
    font-size: 11px; font-weight: 700; color: #2563eb;
    background: #dbeafe; border-radius: 3px;
    padding: 1px 5px;
}
#AppTitle   { color: #1e293b; font-size: 18px; font-weight: 800; }
#AppSub     { color: #94a3b8; font-size: 10px; font-weight: 500; }

/* ── Line edits ────────────────────────────────────────────────────────────── */
QLineEdit {
    background: #ffffff; border: 1px solid #cbd5e1;
    border-radius: 6px; padding: 4px 8px;
    color: #1e293b; font-size: 12px; max-height: 24px;
}
QLineEdit:focus { border-color: #2563eb; background: #eff6ff; }

/* ── Checkboxes ────────────────────────────────────────────────────────────── */
QCheckBox { color: #334155; font-size: 12px; spacing: 8px; }
QCheckBox::indicator {
    width: 16px; height: 16px; border-radius: 4px;
    border: 2px solid #cbd5e1; background: #ffffff;
}
QCheckBox::indicator:checked         { background: #2563eb; border-color: #2563eb; }
QCheckBox::indicator:checked:hover   { background: #1d55d4; }
QCheckBox::indicator:unchecked:hover { border-color: #2563eb; }

/* ── Info (?) button ───────────────────────────────────────────────────────── */
QPushButton#InfoButton {
    background: #e2e8f0; color: #64748b;
    border-radius: 9px; border: 1px solid #cbd5e1;
    font-size: 10px; font-weight: 800;
    min-width: 18px; max-width: 18px;
    min-height: 18px; max-height: 18px; padding: 0;
}
QPushButton#InfoButton:hover { background: #2563eb; color: #fff; border-color: #2563eb; }

/* ── Main action buttons ───────────────────────────────────────────────────── */
QPushButton {
    background: #2563eb; color: #fff;
    font-size: 13px; font-weight: 700;
    padding: 9px 28px; border-radius: 8px;
    border: 2px solid #1d4ed8;
}
QPushButton:hover  { background: #1d55d4; border-color: #1e40af; }
QPushButton#ResetButton       { background: #dc2626; border: 2px solid #b91c1c; }
QPushButton#ResetButton:hover { background: #b91c1c; border-color: #991b1b; }

/* ── Combo box ─────────────────────────────────────────────────────────────── */
QComboBox {
    background: #ffffff; border: 1px solid #e2e8f0;
    border-radius: 6px; padding: 5px 10px;
    color: #1e293b; font-size: 12px; max-height: 28px;
}
QComboBox:focus { border-color: #2563eb; }
QComboBox::drop-down { border: none; width: 20px; }
QComboBox QAbstractItemView {
    background: #ffffff; border: 1px solid #e2e8f0;
    selection-background-color: #2563eb; color: #1e293b;
}
QComboBox#LangCombo {
    background: #1e40af; border: 1px solid #3b82f6;
    border-radius: 6px; padding: 5px 10px;
    color: #ffffff; font-size: 12px; max-height: 28px;
}
QComboBox#LangCombo:focus { border-color: #93c5fd; }
QComboBox#LangCombo::drop-down { border: none; width: 20px; }
QComboBox#LangCombo QAbstractItemView {
    background: #1e3a8a; border: 1px solid #3b82f6;
    selection-background-color: #3b82f6; color: #ffffff;
}

/* ── Plain text edit ───────────────────────────────────────────────────────── */
QPlainTextEdit {
    background: #ffffff; border: 1px solid #cbd5e1;
    border-radius: 6px; padding: 6px;
    color: #1e293b; font-family: 'Consolas', monospace; font-size: 12px;
}
QPlainTextEdit:focus { border-color: #2563eb; }

/* ── Scrollbar ─────────────────────────────────────────────────────────────── */
QScrollArea  { border: none; background: transparent; }
QScrollBar:vertical {
    background: #e2e8f0; width: 7px; border-radius: 4px; margin: 0;
}
QScrollBar::handle:vertical {
    background: #94a3b8; border-radius: 4px; min-height: 30px;
}
QScrollBar::handle:vertical:hover { background: #2563eb; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }

/* ── Disabled ──────────────────────────────────────────────────────────────── */
QWidget:disabled { opacity: 0.35; }

/* ── Message boxes ─────────────────────────────────────────────────────────── */
QMessageBox              { background: #f1f5f9; }
QMessageBox QLabel       { color: #1e293b; background: transparent; }
QMessageBox QPushButton  { min-width: 80px; padding: 6px 16px; font-size: 12px; }
QFrame { border-color: #e2e8f0; }
* { outline: none; }
"""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_scroll_tab():
    tab   = QWidget()
    outer = QVBoxLayout(tab)
    outer.setContentsMargins(0, 0, 0, 0)
    scroll = QScrollArea()
    scroll.setWidgetResizable(True)
    outer.addWidget(scroll)
    content = QWidget()
    content.setObjectName("ScrollContent")
    scroll.setWidget(content)
    layout = QVBoxLayout(content)
    layout.setContentsMargins(14, 14, 14, 14)
    layout.setSpacing(10)
    return tab, layout

def make_group(title: str) -> tuple[QGroupBox, QGridLayout]:
    box  = QGroupBox(title)
    grid = QGridLayout(box)
    grid.setContentsMargins(10, 22, 10, 12)
    grid.setHorizontalSpacing(8)
    grid.setVerticalSpacing(8)
    return box, grid

def make_section_label(text: str) -> QLabel:
    lbl = QLabel(text)
    lbl.setObjectName("SectionLabel")
    return lbl

# ---------------------------------------------------------------------------
# Main Window
# ---------------------------------------------------------------------------

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setObjectName("MainWindow")
        self.field_widgets: dict[str, dict] = {}
        self.admins_edit       = QPlainTextEdit()
        self.moderators_edit   = QPlainTextEdit()
        self.uimpi_admins_edit = QPlainTextEdit()
        self.vote_options_edit = QLineEdit()
        self.roleplay_dependents: list[QWidget] = []
        self.current_lang       = "en"
        self.config_data:       dict = {}
        self.uimpi_config_data: dict = {}
        self._build_ui()
        self._load_config()
        self._load_uimpi_config()
        self._populate_ui()
        self._apply_lang("en")

    # ── Translation ──────────────────────────────────────────────────────────

    def tr(self, key: str) -> str:
        v = EDITOR_TRANSLATIONS.get(self.current_lang, {}).get(key)
        if v: return v
        v = EDITOR_TRANSLATIONS.get("en", {}).get(key)
        return v if v else key

    def tr_tip(self, key: str) -> str:
        lang_tips = EDITOR_TRANSLATIONS.get(self.current_lang, {}).get("tooltips", {})
        tip = lang_tips.get(key)
        if tip: return tip
        return EDITOR_TRANSLATIONS.get("en", {}).get("tooltips", {}).get(key, "")

    def _apply_lang(self, code: str):
        self.current_lang = code
        QApplication.instance().setLayoutDirection(
            Qt.RightToLeft if code in RTL_LANGS else Qt.LeftToRight)
        self._refresh_labels()

    def _on_lang_changed(self, display: str):
        self._apply_lang(LANG_MAP.get(display, "en"))

    def _refresh_labels(self):
        self.setWindowTitle(self.tr("window_title"))
        self.save_btn.setText(self.tr("save_button"))
        self.reset_btn.setText(self.tr("reset_button"))
        for i, k in enumerate(self._tab_keys):
            icon = TAB_ICONS.get(k, "")
            self.tabs.setTabText(i, f"{icon} {self.tr(k)}" if icon else self.tr(k))
        for k, box in self._group_boxes.items():
            icon = GROUP_ICONS.get(k, "")
            box.setTitle(f"{icon}  {self.tr(k)}" if icon else self.tr(k))
        for k, lbl in self._section_labels.items():
            icon = SECTION_ICONS.get(k, "")
            lbl.setText(f"{icon}  {self.tr(k)}" if icon else self.tr(k))
        for cat, key, _ in FIELDS:
            w = self.field_widgets.get(cat, {}).get(key)
            if isinstance(w, QCheckBox):
                w.setText(self.tr(key))
            elif isinstance(w, QLineEdit) and hasattr(w, "_lbl"):
                w._lbl.setText(self.tr(key))
        # UIMPIT admins
        if hasattr(self, "_admins_lbl"):
            self._admins_lbl.setText(self.tr("admins_desc"))
            self._mods_lbl.setText(self.tr("moderators_desc"))
        # UIMPI-specific labels
        if hasattr(self, "_uimpi_admins_lbl"):
            self._uimpi_admins_lbl.setText(self.tr("uimpi_admins_desc"))
        if hasattr(self, "_vote_options_lbl"):
            self._vote_options_lbl.setText(self.tr("vote_options"))
            tip = self.tr_tip("vote_options")
            self._vote_options_lbl.setToolTip(tip)
            self.vote_options_edit.setToolTip(tip)
        # Tooltips for all FIELDS widgets
        for cat, key, _ in FIELDS:
            w = self.field_widgets.get(cat, {}).get(key)
            tip = self.tr_tip(key)
            if isinstance(w, QCheckBox):
                w.setToolTip(tip)
            elif isinstance(w, QLineEdit):
                w.setToolTip(tip)
                if hasattr(w, "_lbl"):
                    w._lbl.setToolTip(tip)

    # ── Build ────────────────────────────────────────────────────────────────

    def _reg(self, cat, key, w): self.field_widgets.setdefault(cat, {})[key] = w

    def _build_ui(self):
        self.setStyleSheet(STYLESHEET)
        self.resize(1000, 740)
        root = QWidget()
        self.setCentralWidget(root)
        vbox = QVBoxLayout(root)
        vbox.setContentsMargins(0, 0, 0, 0)
        vbox.setSpacing(0)

        header_bar = QWidget()
        header_bar.setStyleSheet("background: #1e3a8a; border-bottom: 2px solid #1d4ed8;")
        header_bar.setFixedHeight(64)
        hl = QHBoxLayout(header_bar)
        hl.setContentsMargins(20, 0, 20, 0)
        hl.addLayout(self._build_header())
        vbox.addWidget(header_bar)

        tab_area = QWidget()
        tab_area.setStyleSheet("background: #f1f5f9;")
        tl = QVBoxLayout(tab_area)
        tl.setContentsMargins(16, 12, 16, 0)
        self.tabs = QTabWidget()
        tl.addWidget(self.tabs)
        vbox.addWidget(tab_area, 1)

        self._tab_keys = [
            "tab_features", "tab_economy", "tab_civilian", "tab_police",
            "tab_markers",  "tab_air_polluter", "tab_admins", "tab_timers",
            "tab_uimpi",
        ]
        self._group_boxes:    dict[str, QGroupBox] = {}
        self._section_labels: dict[str, QLabel]   = {}

        for builder in [
            self._tab_features, self._tab_economy,      self._tab_civilian,
            self._tab_police,   self._tab_markers,       self._tab_air_polluter,
            self._tab_admins,   self._tab_timers,        self._tab_uimpi,
        ]:
            self.tabs.addTab(builder(), "")

        footer_bar = QWidget()
        footer_bar.setStyleSheet("background: #1e3a8a; border-top: 2px solid #1d4ed8;")
        footer_bar.setFixedHeight(56)
        fl = QHBoxLayout(footer_bar)
        fl.setContentsMargins(20, 0, 20, 0)
        fl.addLayout(self._build_footer())
        vbox.addWidget(footer_bar)

    def _build_header(self):
        h = QHBoxLayout()
        h.setAlignment(Qt.AlignCenter)
        title_row = QHBoxLayout()
        title_row.setSpacing(8)
        title_row.setAlignment(Qt.AlignCenter)
        def title_part(text, color):
            lbl = QLabel(text)
            lbl.setStyleSheet(
                f"color:{color}; font-size:22px; font-weight:900;"
                "font-family:'Segoe UI',Arial,sans-serif; background:transparent;"
            )
            return lbl
        title_row.addWidget(title_part("PIT", "#ffffff"))
        title_row.addWidget(title_part("·", "#93c5fd"))
        title_row.addWidget(title_part("🚗 Cops", "#fca5a5"))
        title_row.addWidget(title_part("n", "#ffffff"))
        title_row.addWidget(title_part("Wanted 🚔", "#93c5fd"))
        center = QVBoxLayout()
        center.setSpacing(2)
        center.setAlignment(Qt.AlignCenter)
        center.addLayout(title_row)
        sub = QLabel("Server Configuration Editor")
        sub.setStyleSheet("color:#93c5fd; font-size:10px; font-weight:500; background:transparent;")
        sub.setAlignment(Qt.AlignCenter)
        center.addWidget(sub)
        h.addLayout(center)
        return h

    def _build_footer(self):
        h = QHBoxLayout()
        globe = QLabel("🌐")
        globe.setStyleSheet("font-size: 15px; background: transparent; color: #ffffff;")
        self.lang_cb = QComboBox()
        self.lang_cb.setObjectName("LangCombo")
        self.lang_cb.setFixedWidth(120)
        for code in SUPPORTED_LANGS:
            name = EDITOR_TRANSLATIONS.get(code, {}).get("lang_name", code)
            self.lang_cb.addItem(name)
        self.lang_cb.currentTextChanged.connect(self._on_lang_changed)
        self.lang_cb.view().window().setWindowFlags(
            self.lang_cb.view().window().windowFlags() | Qt.NoDropShadowWindowHint
        )
        h.addWidget(globe)
        h.addWidget(self.lang_cb)
        h.addStretch()
        self.reset_btn = QPushButton()
        self.reset_btn.setObjectName("ResetButton")
        self.reset_btn.clicked.connect(self._reset)
        self.save_btn = QPushButton()
        self.save_btn.clicked.connect(self._save)
        h.addWidget(self.reset_btn)
        h.addWidget(self.save_btn)
        return h

    # ── Shared widget helpers ─────────────────────────────────────────────────

    def _make_info_btn(self, key: str) -> QPushButton:
        btn = QPushButton("?")
        btn.setObjectName("InfoButton")
        btn.setFixedSize(18, 18)
        btn.setCursor(Qt.WhatsThisCursor)
        btn.clicked.connect(
            lambda _, b=btn, k=key: QToolTip.showText(
                b.mapToGlobal(QPoint(0, b.height() + 4)),
                self.tr_tip(k), b, QRect(), 8000
            )
        )
        return btn

    def _entry(self, cat: str, key: str, ftype: str,
               grid: QGridLayout, row: int, col: int):
        type_key = _field_type(key)
        _, _, bar_bg, bar_color = _TYPE_META.get(type_key, _TYPE_META["count"])

        card = QWidget()
        card.setObjectName("FieldCard")
        card.setFixedHeight(72)
        card_h = QHBoxLayout(card)
        card_h.setContentsMargins(0, 0, 0, 0)
        card_h.setSpacing(0)

        bar = QWidget()
        bar.setFixedWidth(4)
        bar.setStyleSheet(f"background:{bar_color}; border-radius:4px 0 0 4px; border:none;")
        card_h.addWidget(bar)

        content = QWidget()
        content.setStyleSheet("background:transparent; border:none;")
        vb = QVBoxLayout(content)
        vb.setContentsMargins(10, 6, 8, 4)
        vb.setSpacing(2)
        card_h.addWidget(content, 1)

        top = QHBoxLayout()
        top.setSpacing(6)
        top.setContentsMargins(0, 0, 0, 0)
        badge = _make_badge(type_key)
        lbl   = QLabel(self.tr(key))
        lbl.setObjectName("FieldLabel")
        info  = self._make_info_btn(key)
        top.addWidget(badge)
        top.addWidget(lbl, 1)
        top.addWidget(info)

        edit = QLineEdit()
        edit.setFixedHeight(24)
        if ftype == "float":
            v = QDoubleValidator(0.0, 999999.0, 3)
            v.setNotation(QDoubleValidator.StandardNotation)
            edit.setValidator(v)
        else:
            edit.setValidator(QIntValidator(0, 999_999_999))
        edit._lbl = lbl

        tip = self.tr_tip(key)
        if tip:
            lbl.setToolTip(tip)
            edit.setToolTip(tip)

        hint = QLabel("")
        hint.setObjectName("TimeHint")
        hint.setFixedHeight(12)
        if is_time_key(key):
            edit.textChanged.connect(lambda txt, h=hint, k=key: h.setText(fmt_time(txt, k)))
        edit._hint = hint

        vb.addLayout(top)
        vb.addWidget(edit)
        vb.addWidget(hint)

        grid.addWidget(card, row, col, Qt.AlignTop)
        self._reg(cat, key, edit)

    def _checkbox(self, cat, key, grid, row, col, dependent=False):
        container = QWidget()
        container.setStyleSheet("background:transparent; border:none;")
        h = QHBoxLayout(container)
        h.setContentsMargins(6, 4, 6, 4)
        h.setSpacing(6)
        cb   = QCheckBox(self.tr(key))
        info = self._make_info_btn(key)
        h.addWidget(cb)
        h.addWidget(info)
        h.addStretch()
        if dependent:
            self.roleplay_dependents.append(cb)
        grid.addWidget(container, row, col)
        self._reg(cat, key, cb)
        return cb

    def _section(self, grid, row, key):
        icon = SECTION_ICONS.get(key, "")
        text = f"{icon}  {self.tr(key)}" if icon else self.tr(key)
        lbl  = make_section_label(text)
        self._section_labels[key] = lbl
        grid.addWidget(lbl, row, 0, 1, -1)

    # ── Tabs ──────────────────────────────────────────────────────────────────

    def _tab_features(self):
        tab, layout = make_scroll_tab()
        box, grid = make_group("")
        self._group_boxes["features_title"] = box
        grid.setHorizontalSpacing(4)
        rp = self._checkbox("features","roleplay_enabled",               grid,0,0)
        self._checkbox("features","money_per_minute_enabled",       grid,0,1)
        self._checkbox("features","cool_message_enabled",           grid,0,2)
        self._checkbox("features","police_features_enabled",        grid,1,0,dependent=True)
        self._checkbox("features","speeding_bonus_enabled",         grid,1,1,dependent=True)
        self._checkbox("features","zigzag_bonus_enabled",           grid,1,2,dependent=True)
        self._checkbox("features","spawn_teleport_enabled",         grid,2,0)
        self._checkbox("features","markers_enabled",                grid,2,1)
        self._checkbox("features","ranks_enabled",                  grid,2,2)
        self._checkbox("features","playerlist_custom_data_enabled", grid,3,0)
        rp.stateChanged.connect(self._apply_roleplay_deps)
        layout.addWidget(box)
        layout.addStretch()
        return tab

    def _tab_economy(self):
        tab, layout = make_scroll_tab()
        g1, gr1 = make_group(""); self._group_boxes["general_title"] = g1
        self._entry("general","autosave_interval_ms","int",gr1,0,0)
        layout.addWidget(g1)
        g2, gr2 = make_group(""); self._group_boxes["money_title"] = g2
        self._entry("money","starting_money",               "int",gr2,0,0)
        self._entry("money","money_per_minute_amount",      "int",gr2,0,1)
        self._entry("money","money_per_minute_interval_ms", "int",gr2,0,2)
        self._entry("money","cool_message_interval_ms",     "int",gr2,1,0)
        layout.addWidget(g2)
        layout.addStretch()
        return tab

    def _tab_civilian(self):
        tab, layout = make_scroll_tab()
        box, grid = make_group(""); self._group_boxes["civilian_title"] = box
        self.roleplay_dependents.append(box)
        self._section(grid, 0, "section_speeding")
        self._entry("civilian","speeding_limit_kmh",           "int",  grid,1,0)
        self._entry("civilian","speeding_bonus_per_second",    "int",  grid,1,1)
        self._entry("civilian","speeding_final_bonus_amount",  "int",  grid,1,2)
        self._entry("civilian","speeding_bonus_duration_ms",   "int",  grid,2,0)
        self._entry("civilian","speeding_cooldown_ms",         "int",  grid,2,1)
        self._entry("civilian","speeding_allowed_repairs",     "int",  grid,2,2)
        self._section(grid, 3, "section_zigzag")
        self._entry("civilian","min_speed_kmh_for_zigzag",          "int",  grid,4,0)
        self._entry("civilian","zigzag_min_turns",                  "int",  grid,4,1)
        self._entry("civilian","zigzag_min_angle_degrees",          "int",  grid,4,2)
        self._entry("civilian","zigzag_max_turn_interval_seconds",  "float",grid,5,0)
        self._entry("civilian","zigzag_prorated_bonus",             "int",  grid,5,1)
        self._entry("civilian","zigzag_final_bonus_amount",         "int",  grid,5,2)
        self._entry("civilian","zigzag_bonus_duration_ms",          "int",  grid,6,0)
        self._entry("civilian","zigzag_cooldown_ms",                "int",  grid,6,1)
        self._entry("civilian","zigzag_allowed_repairs",            "int",  grid,6,2)
        self._section(grid, 7, "section_misc")
        self._entry("civilian","combo_allowed_repairs",    "int",grid,8,0)
        self._entry("civilian","wanted_fail_penalty",      "int",grid,8,1)
        self._entry("civilian","max_speed_for_repair_kmh", "int",grid,8,2)
        layout.addWidget(box)
        layout.addStretch()
        return tab

    def _tab_police(self):
        tab, layout = make_scroll_tab()
        box, grid = make_group(""); self._group_boxes["police_title"] = box
        self.roleplay_dependents.append(box)
        self._entry("police","police_proximity_range_m","int",grid,0,0)
        self._entry("police","busted_range_m",          "int",grid,0,1)
        self._entry("police","busted_stop_time_ms",     "int",grid,0,2)
        self._entry("police","busted_speed_limit_kmh",  "int",grid,1,0)
        self._entry("police","police_bonus_per_second", "int",grid,1,1)
        self._entry("police","bust_bonus_amount",       "int",grid,1,2)
        self._entry("police","police_allowed_repairs",  "int",grid,2,0)
        self._entry("police","repair_proximity_limit_m","int",grid,2,1)
        layout.addWidget(box)
        sys_box, sg = make_group(""); self._group_boxes["system_title"] = sys_box
        self._entry("system","repair_reset_time_seconds",       "int",sg,0,0)
        self._entry("system","chase_accumulator_chunk_seconds", "int",sg,0,1)
        self._entry("system","teleport_cooldown_seconds",       "int",sg,0,2)
        self._entry("system","repair_approval_window_seconds",  "int",sg,1,0)
        self._entry("system","repair_proximity_limit_m",        "int",sg,1,1)
        layout.addWidget(sys_box)
        layout.addStretch()
        return tab

    def _tab_markers(self):
        tab, layout = make_scroll_tab()
        box, grid = make_group(""); self._group_boxes["markers_title"] = box
        self._entry("markers","spawn_delay_ms",       "int",grid,0,0)
        self._entry("markers","max_markers",          "int",grid,0,1)
        self._entry("markers","marker_type",          "int",grid,0,2)
        self._entry("markers","marker_scale",         "int",grid,1,0)
        self._entry("markers","marker_reward_amount", "int",grid,1,1)
        layout.addWidget(box)
        col_box, cg = make_group(""); self._group_boxes["marker_color_title"] = col_box
        for i, ch in enumerate(("r","g","b","a")):
            self._entry("marker_color", ch, "int", cg, 0, i)
        layout.addWidget(col_box)
        layout.addStretch()
        return tab

    def _tab_air_polluter(self):
        tab, layout = make_scroll_tab()
        box, grid = make_group(""); self._group_boxes["air_polluter_title"] = box
        self._entry("air_polluter","min_players",    "int",grid,0,0)
        self._entry("air_polluter","cooldown_secs",  "int",grid,0,1)
        self._entry("air_polluter","hover_radius_m", "int",grid,0,2)
        self._entry("air_polluter","touch_radius_m", "int",grid,1,0)
        layout.addWidget(box)
        layout.addStretch()
        return tab

    def _tab_admins(self):
        tab, layout = make_scroll_tab()
        a_box, ag = make_group(""); self._group_boxes["admins_title"] = a_box
        self._admins_lbl = QLabel(); self._admins_lbl.setObjectName("FieldLabel")
        self.admins_edit.setPlaceholderText("PlayerName1\nPlayerName2")
        self.admins_edit.setFixedHeight(100)
        ag.addWidget(self._admins_lbl, 0, 0)
        ag.addWidget(self.admins_edit, 1, 0)
        layout.addWidget(a_box)
        m_box, mg = make_group(""); self._group_boxes["moderators_title"] = m_box
        self._mods_lbl = QLabel(); self._mods_lbl.setObjectName("FieldLabel")
        self.moderators_edit.setPlaceholderText("PlayerName1\nPlayerName2")
        self.moderators_edit.setFixedHeight(100)
        mg.addWidget(self._mods_lbl, 0, 0)
        mg.addWidget(self.moderators_edit, 1, 0)
        layout.addWidget(m_box)
        layout.addStretch()
        return tab

    def _tab_timers(self):
        tab, layout = make_scroll_tab()
        box, grid = make_group(""); self._group_boxes["timers_title"] = box
        keys = ["welcome_checker_ms","fast_marker_check_ms","combined_checker_ms","role_checker_ms",
                "zigzag_checker_ms","money_sync_ms","rank_save_ms","rank_ui_update_ms",
                "police_wanted_update_ms","editing_position_sync_ms"]
        for i, k in enumerate(keys):
            self._entry("timers", k, "int", grid, i // 3, i % 3)
        layout.addWidget(box)
        layout.addStretch()
        return tab

    def _tab_uimpi(self):
        tab, layout = make_scroll_tab()

        # ── General settings ─────────────────────────────────────────────────
        g1, gr1 = make_group(""); self._group_boxes["uimpi_general_title"] = g1
        self._entry("uimpi", "max_performance_rating", "int", gr1, 0, 0)
        self._entry("uimpi", "display_offset",         "int", gr1, 0, 1)
        layout.addWidget(g1)

        # ── Vote system ──────────────────────────────────────────────────────
        g2, gr2 = make_group(""); self._group_boxes["uimpi_vote_title"] = g2

        self._checkbox("uimpi", "vote_enabled", gr2, 0, 0)
        self._entry("uimpi", "vote_duration", "int", gr2, 1, 0)

        # vote_options — custom card (comma-separated, no int validator)
        vo_type_key = "count"
        _, _, _, vo_bar_color = _TYPE_META[vo_type_key]
        vo_card = QWidget(); vo_card.setObjectName("FieldCard"); vo_card.setFixedHeight(72)
        vo_h = QHBoxLayout(vo_card); vo_h.setContentsMargins(0,0,0,0); vo_h.setSpacing(0)
        vo_accent = QWidget(); vo_accent.setFixedWidth(4)
        vo_accent.setStyleSheet(f"background:{vo_bar_color}; border-radius:4px 0 0 4px; border:none;")
        vo_h.addWidget(vo_accent)
        vo_content = QWidget(); vo_content.setStyleSheet("background:transparent; border:none;")
        vo_vb = QVBoxLayout(vo_content); vo_vb.setContentsMargins(10,6,8,4); vo_vb.setSpacing(2)
        vo_top = QHBoxLayout(); vo_top.setSpacing(6); vo_top.setContentsMargins(0,0,0,0)
        vo_badge = _make_badge(vo_type_key)
        self._vote_options_lbl = QLabel(self.tr("vote_options"))
        self._vote_options_lbl.setObjectName("FieldLabel")
        vo_info = self._make_info_btn("vote_options")
        vo_top.addWidget(vo_badge)
        vo_top.addWidget(self._vote_options_lbl, 1)
        vo_top.addWidget(vo_info)
        self.vote_options_edit.setFixedHeight(24)
        self.vote_options_edit.setPlaceholderText("80, 100, 120, 150, 200, 250")
        vo_hint = QLabel(""); vo_hint.setObjectName("TimeHint"); vo_hint.setFixedHeight(12)
        vo_vb.addLayout(vo_top)
        vo_vb.addWidget(self.vote_options_edit)
        vo_vb.addWidget(vo_hint)
        vo_h.addWidget(vo_content, 1)
        gr2.addWidget(vo_card, 2, 0, 1, 2, Qt.AlignTop)

        layout.addWidget(g2)

        # ── Admins ───────────────────────────────────────────────────────────
        a_box, ag = make_group(""); self._group_boxes["uimpi_admins_title"] = a_box
        self._uimpi_admins_lbl = QLabel(); self._uimpi_admins_lbl.setObjectName("FieldLabel")
        self.uimpi_admins_edit.setPlaceholderText("PlayerName1\nPlayerName2")
        self.uimpi_admins_edit.setFixedHeight(100)
        ag.addWidget(self._uimpi_admins_lbl, 0, 0)
        ag.addWidget(self.uimpi_admins_edit,  1, 0)
        layout.addWidget(a_box)

        layout.addStretch()
        return tab

    # ── Roleplay deps ─────────────────────────────────────────────────────────

    def _apply_roleplay_deps(self):
        w  = self.field_widgets.get("features",{}).get("roleplay_enabled")
        on = w.isChecked() if isinstance(w, QCheckBox) else True
        for d in self.roleplay_dependents: d.setEnabled(on)

    # ── Config I/O ────────────────────────────────────────────────────────────

    def _load_config(self):
        try:
            with open(UIMPIT_CONFIG, encoding="utf-8") as f:
                self.config_data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            self.config_data = {}
        for cat, fields in FALLBACK_DEFAULTS.items():
            if isinstance(fields, dict):
                self.config_data.setdefault(cat, {})
                for k, v in fields.items():
                    self.config_data[cat].setdefault(k, v)
            else:
                self.config_data.setdefault(cat, fields)

    def _load_uimpi_config(self):
        try:
            with open(UIMPI_CONFIG, encoding="utf-8") as f:
                self.uimpi_config_data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            self.uimpi_config_data = {}
        for k, v in UIMPI_FALLBACK_DEFAULTS.items():
            self.uimpi_config_data.setdefault(k, v)

    def _populate_ui(self):
        for cat, key, _ in FIELDS:
            w = self.field_widgets.get(cat, {}).get(key)
            if w is None: continue
            if cat == "uimpi":
                val = self.uimpi_config_data.get(key)
            elif cat == "marker_color":
                val = self.config_data.get("markers",{}).get("marker_color",{}).get(key)
            else:
                val = self.config_data.get(cat,{}).get(key)
            if val is None: continue
            if isinstance(w, QCheckBox):
                w.setChecked(bool(val))
            elif isinstance(w, QLineEdit):
                w.setText(str(val))
                if hasattr(w, "_hint"):
                    w._hint.setText(fmt_time(str(val), key))

        parse_list = lambda lst: "\n".join(str(x) for x in lst)
        self.admins_edit.setPlainText(parse_list(self.config_data.get("admins", [])))
        self.moderators_edit.setPlainText(parse_list(self.config_data.get("moderators", [])))
        self.uimpi_admins_edit.setPlainText(parse_list(self.uimpi_config_data.get("admins", [])))
        opts = self.uimpi_config_data.get("vote_options", [])
        self.vote_options_edit.setText(", ".join(str(v) for v in opts))
        self._apply_roleplay_deps()

    def _save(self):
        try:
            parse = lambda t: [l.strip() for l in t.splitlines() if l.strip()]

            # ── UIMPIT fields ────────────────────────────────────────────────
            for cat, key, ftype in FIELDS:
                if cat == "uimpi": continue
                w = self.field_widgets.get(cat,{}).get(key)
                if w is None: continue
                if isinstance(w, QCheckBox):
                    val = w.isChecked()
                elif isinstance(w, QLineEdit):
                    val = float(w.text().strip()) if ftype == "float" else int(w.text().strip() or 0)
                else:
                    continue
                if cat == "marker_color":
                    self.config_data.setdefault("markers",{}).setdefault("marker_color",{})[key] = val
                else:
                    self.config_data.setdefault(cat,{})[key] = val
            self.config_data["admins"]     = parse(self.admins_edit.toPlainText())
            self.config_data["moderators"] = parse(self.moderators_edit.toPlainText())
            os.makedirs(os.path.dirname(UIMPIT_CONFIG), exist_ok=True)
            with open(UIMPIT_CONFIG, "w", encoding="utf-8") as f:
                json.dump(self.config_data, f, indent=2, ensure_ascii=False)

            # ── UIMPI fields ─────────────────────────────────────────────────
            for cat, key, ftype in FIELDS:
                if cat != "uimpi": continue
                w = self.field_widgets.get("uimpi",{}).get(key)
                if w is None: continue
                if isinstance(w, QCheckBox):
                    val = w.isChecked()
                elif isinstance(w, QLineEdit):
                    val = int(w.text().strip() or 0)
                else:
                    continue
                self.uimpi_config_data[key] = val
            raw = self.vote_options_edit.text()
            self.uimpi_config_data["vote_options"] = [
                int(x.strip()) for x in raw.split(",")
                if x.strip().lstrip("-").isdigit()
            ]
            self.uimpi_config_data["admins"] = parse(self.uimpi_admins_edit.toPlainText())
            os.makedirs(os.path.dirname(UIMPI_CONFIG), exist_ok=True)
            with open(UIMPI_CONFIG, "w", encoding="utf-8") as f:
                json.dump(self.uimpi_config_data, f, indent=2, ensure_ascii=False)

            QMessageBox.information(self, self.tr("success_save_title"), self.tr("success_save_message"))
        except Exception as e:
            QMessageBox.critical(self, self.tr("error_title"), f"{self.tr('error_invalid_input')}\n\n{e}")

    def _reset(self):
        if QMessageBox.question(
            self, self.tr("confirm_reset_title"), self.tr("confirm_reset_message"),
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        ) == QMessageBox.Yes:
            self.config_data       = copy.deepcopy(FALLBACK_DEFAULTS)
            self.uimpi_config_data = copy.deepcopy(UIMPI_FALLBACK_DEFAULTS)
            self._populate_ui()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    win = MainWindow()
    win.show()
    sys.exit(app.exec())
