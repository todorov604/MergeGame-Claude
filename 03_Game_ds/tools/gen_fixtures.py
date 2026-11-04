#!/usr/bin/env python3
"""Generate validator fixtures for 03_Game_ds.

One mutation per file, everything else stays valid, so a failing fixture points at
exactly one rule. Re-runnable.

    python tools/gen_fixtures.py
"""

import copy
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "tests", "fixtures")
BROKEN = os.path.join(FIXTURES, "broken")

BASE = {
    "version": 2,
    "meta": {"title": "min", "resolution": [1080, 1920], "fps": 60, "locale": "zh"},
    "theme": "themes/default",
    "locales": {"zh": {"cta.play": "立即游玩", "hook.question": "它能合成吗？"}},
    "hud": {
        "level": 1,
        "energy": 10,
        "energyTickSeconds": 120,
        "energyTickMode": "decrement",
        "coin": 0,
        "star": 0,
        "gem": 0,
        "exp": 0,
    },
    "entities": {
        "A": {"kind": "chip", "family": "Clean", "chain": "a", "maxLevel": 10,
              "visual": {"hue": "#F2A65A", "label": "A"}},
        "B": {"kind": "chip", "family": "Clean", "chain": "b", "maxLevel": 10,
              "visual": {"hue": "#7FB069", "label": "B"}},
        "G": {"kind": "generator", "maxLevel": 3, "visual": {"hue": "#5B8DEF", "label": "G"}},
        "C1": {"kind": "character", "visual": {"hue": "#E9C46A", "label": "C1"}},
    },
    "generators": {"G": {"charges": 3, "cooldown": 0, "outputs": [{"entity": "A", "weight": 1}]}},
    "characters": {"C1": {"display": "阿奶"}},
    "levels": [
        {
            "id": "level_1",
            "board": {
                "width": 7,
                "height": 9,
                "slots": [
                    {"x": 0, "y": 0, "entity": "G", "level": 1},
                    {"x": 1, "y": 1, "entity": "A", "level": 1},
                    {"x": 2, "y": 1, "entity": "A", "level": 1},
                ],
            },
            "obstacles": [{"slot": [0, 1], "type": "web"}],
            "orders": [
                {"id": "order_1", "character": "C1", "mission": [{"entity": "A", "level": 2}],
                 "star": 1, "coin": 5}
            ],
        }
    ],
    "timeline": [
        {"id": "e1", "channel": "sim", "type": "merge", "at": 1.0, "duration": 0.3,
         "payload": {"from": [1, 1], "to": [2, 1]}},
        {"id": "e2", "channel": "sim", "type": "order_claim", "at": 3.0,
         "payload": {"order": "order_1"}},
        {"id": "e3", "channel": "view", "type": "cta", "at": 5.0, "duration": 2.0,
         "payload": {"text_key": "cta.play"}},
    ],
}


def base():
    return copy.deepcopy(BASE)


def slot(p, x, y):
    return next(s for s in p["levels"][0]["board"]["slots"] if s["x"] == x and s["y"] == y)


def m_version(p):
    p["version"] = 3


def m_next(p):
    p["levels"][0]["next"] = "level_2"


def m_slot_entity(p):
    p["levels"][0]["board"]["slots"].append({"x": 3, "y": 3, "entity": "A2", "level": 1})


def m_generator_output(p):
    p["generators"]["G"]["outputs"].append({"entity": "A_undefined", "weight": 1})


def m_generator_kind(p):
    p["entities"]["G"]["kind"] = "special"
    p["entities"]["G"].pop("maxLevel", None)


def m_slot_level(p):
    slot(p, 1, 1)["level"] = 11


def m_maxlevel(p):
    p["entities"]["A"]["maxLevel"] = 11


def m_order_unreachable(p):
    p["levels"][0]["orders"][0]["mission"] = [{"entity": "B", "level": 5}]


def m_obstacle_type(p):
    p["levels"][0]["obstacles"][0]["type"] = "slime"


def m_slot_dup(p):
    p["levels"][0]["board"]["slots"].append({"x": 1, "y": 1, "entity": "A", "level": 2})


def m_slot_oob(p):
    p["levels"][0]["board"]["slots"].append({"x": 7, "y": 8, "entity": "A", "level": 1})


def m_slot_chip_key(p):
    p["levels"][0]["board"]["slots"][1]["chip"] = "A"


def m_generator_nonbehavior(p):
    p["generators"]["G"]["entity"] = "A"


def m_wait(p):
    p["timeline"].append({"id": "e9", "channel": "sim", "type": "wait", "at": 6.0, "payload": {}})


def m_anchor_missing(p):
    p["timeline"].append({"id": "e4", "channel": "view", "type": "text",
                          "at": {"after": "e999", "offset": 0.1},
                          "payload": {"text_key": "cta.play"}})


def m_anchor_cycle(p):
    p["timeline"].append({"id": "e4", "channel": "view", "type": "text",
                          "at": {"after": "e5", "offset": 0.1},
                          "payload": {"text_key": "cta.play"}})
    p["timeline"].append({"id": "e5", "channel": "view", "type": "text",
                          "at": {"after": "e4", "offset": 0.1},
                          "payload": {"text_key": "cta.play"}})


def m_dup_event_id(p):
    p["timeline"].append({"id": "e1", "channel": "view", "type": "camera", "at": 9.0, "payload": {}})


def m_meta_duration(p):
    p["meta"]["duration"] = 30


def m_hud_missing(p):
    p["hud"].pop("star")


def m_ref_only(p):
    p["entities"]["A"]["visual"]["icon"] = "chip_clean_ca_lv01"


def m_placeholder_no_flag(p):
    p["entities"]["A"]["visual"]["icon"] = "board_frame"


def m_todo_audio(p):
    p["timeline"].append({"id": "a1", "channel": "audio", "type": "bgm", "at": 0.0,
                          "payload": {"resource_id": "audio_bgm"}})


def m_theme_missing(p):
    p["theme"] = "themes/nope"


def m_locale_key(p):
    p["timeline"][2]["payload"]["text_key"] = "nope.key"


# name -> (mutation, expected error code, needs_strict, allow_placeholders)
BROKEN_CASES = {
    "bad_version.json": (m_version, "SCHEMA_VERSION", False, True),
    "bad_next.json": (m_next, "LEVEL_NEXT_REMOVED", False, True),
    "bad_slot_entity.json": (m_slot_entity, "REF_UNDEFINED", False, True),
    "bad_generator_output.json": (m_generator_output, "REF_UNDEFINED", False, True),
    "bad_generator_kind.json": (m_generator_kind, "REF_KIND_MISMATCH", False, True),
    "bad_slot_level.json": (m_slot_level, "SLOT_LEVEL_RANGE", False, True),
    "bad_maxlevel.json": (m_maxlevel, "ENTITY_MAX_LEVEL", False, True),
    "bad_order_unreachable.json": (m_order_unreachable, "ORDER_UNREACHABLE", False, True),
    "bad_obstacle_type.json": (m_obstacle_type, "OBSTACLE_TYPE", False, True),
    "bad_slot_dup.json": (m_slot_dup, "SLOT_DUP", False, True),
    "bad_slot_oob.json": (m_slot_oob, "SLOT_OOB", False, True),
    "bad_slot_chip_key.json": (m_slot_chip_key, "SLOT_CHIP_KEY_LEGACY", False, True),
    "bad_generator_nonbehavior.json": (m_generator_nonbehavior, "GEN_NON_BEHAVIOR_FIELD", False, True),
    "bad_wait.json": (m_wait, "EV_WAIT_FORBIDDEN", False, True),
    "bad_anchor_missing.json": (m_anchor_missing, "EV_ANCHOR_MISSING", False, True),
    "bad_anchor_cycle.json": (m_anchor_cycle, "EV_ANCHOR_CYCLE", False, True),
    "bad_dup_event_id.json": (m_dup_event_id, "EV_DUP_ID", False, True),
    "bad_meta_duration.json": (m_meta_duration, "META_DURATION_PRESENT", True, True),
    "bad_hud_missing.json": (m_hud_missing, "HUD_MISSING_FIELD", False, True),
    "bad_ref_only.json": (m_ref_only, "ASSET_REFERENCE_ONLY", False, True),
    "bad_placeholder_no_flag.json": (m_placeholder_no_flag, "ASSET_PLACEHOLDER_BLOCKED", False, False),
    "bad_todo_audio.json": (m_todo_audio, "ASSET_TODO", False, True),
    "bad_theme_missing.json": (m_theme_missing, "THEME_MISSING", False, True),
    "bad_locale_key.json": (m_locale_key, "LOCALE_KEY_MISSING", False, True),
}


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main():
    write(os.path.join(FIXTURES, "ok_min.json"), base())

    ok_placeholder = base()
    ok_placeholder["theme"] = "themes/placeholder"
    write(os.path.join(FIXTURES, "ok_with_placeholders.json"), ok_placeholder)

    for name, (mut, code, strict, allow) in BROKEN_CASES.items():
        p = base()
        mut(p)
        write(os.path.join(BROKEN, name), p)

    manifest = {
        "note": "generated; consumed by tests/t_validator.gd",
        "cases": [
            {
                "file": "res://tests/fixtures/broken/" + name,
                "code": code,
                "strict": strict,
                "allow_placeholders": allow,
            }
            for name, (mut, code, strict, allow) in BROKEN_CASES.items()
        ],
    }
    write(os.path.join(FIXTURES, "cases.json"), manifest)
    print("fixtures: ok_min, ok_with_placeholders, %d broken cases" % len(BROKEN_CASES))


if __name__ == "__main__":
    main()
