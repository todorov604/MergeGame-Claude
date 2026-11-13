"""生成器新产出逻辑：6 个自造 case（工程 + take），供出片与截图为证。

case1 普通·真随机（订单 Ca4 + Cb3，连点 6 次）
case2 普通·指定顺序（Ca2, Cb3, Ce1；点 4 次：前 3 按序，第 4 次转随机）
case3 每台独立队列（两台 GEN，各配一条；左右各点 1 次）
case4 库存·飞棋子（count=2，点 3 次，第 3 次应无效）
case5 库存·飞生成器（只一次；第 2 次无效；再点落地生成器出货）
case6 关卡差异（L1 随机 / L2 顺序；各点 2 次）
"""
import json
from pathlib import Path

OUT = Path('03_Game_ds/output/probe')
OUT.mkdir(parents=True, exist_ok=True)
SRC = json.loads(Path('03_Game_ds/data/sample_project.json').read_text(encoding='utf-8'))

BX, BY, BW, BH = 48, 466, 983, 1263
COLS, ROWS = 7, 9


def cell_center(cx, cy):
    return [round(BX + (cx + 0.5) * BW / COLS), round(BY + (cy + 0.5) * BH / ROWS)]


def base(level_specs, hud=None):
    p = {
        "version": 2,
        "meta": {"title": "gen probe", "resolution": [1080, 1920], "fps": 60, "locale": "zh"},
        "theme": "themes/default",
        "locales": SRC.get("locales", {}),
        "hud": hud or {"level": 1, "energy": 9999, "energyTickSeconds": 120,
                       "energyTickMode": "decrement", "coin": 0, "gem": 0, "exp": 0},
        "entities": SRC["entities"],
        "generators": SRC["generators"],
        "characters": SRC["characters"],
        "levels": level_specs,
        "timeline": [],
    }
    return p


def lvl(id_, slots, orders, stockpile=None, number=1):
    lv = {"id": id_, "level_number": number,
          "board": {"width": COLS, "height": ROWS, "slots": slots},
          "obstacles": [], "safes": [], "orders": orders}
    if stockpile is not None:
        lv["stockpile"] = stockpile
    return lv


def order(oid, char, mission, coin=5):
    return {"id": oid, "character": char, "coin": coin, "gem": 0, "energy": 0,
            "mission": [{"entity": e, "level": l, "count": 1} for (e, l) in mission]}


CH = next(iter(SRC["characters"]))
GEN_SLOT = lambda x, y, **kw: dict({"x": x, "y": y, "entity": "CleanBox_C", "level": 1}, **kw)

CASES = {}

# ---------------- case1: 真随机
CASES['case1_random'] = {
    "project": base([lvl("gen_random", [GEN_SLOT(1, 1)], [
        order("o1", CH, [("CleanSet_Ca", 4)]),
        order("o2", CH, [("CleanSet_Cb", 3)]),
    ])]),
    "taps": [("tap", 1, 1)] * 6,
}

# ---------------- case2: 顺序 → 转随机
CASES['case2_sequence'] = {
    "project": base([lvl("gen_sequence", [GEN_SLOT(1, 1, mode="sequence", sequence=[
        {"entity": "CleanSet_Ca", "level": 2},
        {"entity": "CleanSet_Cb", "level": 3},
        {"entity": "CleanSet_Ce", "level": 1},
    ])], [
        order("o1", CH, [("CleanSet_Ca", 4)]),
        order("o2", CH, [("CleanSet_Cb", 3)]),
    ])]),
    "taps": [("tap", 1, 1)] * 4,
}

# ---------------- case3: 每台独立
CASES['case3_per_cell'] = {
    "project": base([lvl("gen_per_cell", [
        GEN_SLOT(1, 1, mode="sequence", sequence=[{"entity": "CleanSet_Ce", "level": 2}]),
        GEN_SLOT(5, 1, mode="sequence", sequence=[{"entity": "CleanSet_Cl", "level": 3}]),
    ], [order("o1", CH, [("CleanSet_Ca", 2)])])]),
    "taps": [("tap", 5, 1), ("tap", 1, 1)],
}

# ---------------- case4: 库存飞棋子 count=2
CASES['case4_stockpile_chip'] = {
    "project": base([lvl("sp_chip", [], [order("o1", CH, [("CleanSet_Ca", 3)])],
        stockpile={"enabled": True, "count": 2, "drop": "chip", "generator": "CleanBox_P",
                   "mode": "sequence",
                   "sequence": [{"entity": "CleanSet_Cf", "level": 2}, {"entity": "CleanSet_Ck", "level": 2}]})]),
    # 第 3 次是"应被拒绝"的一击：成片把 rejected 当失败，所以只拍前两次；
    # 拒绝的证据在 tools/probe_gen_trace.gd 的文字轨迹里（SIM_STOCKPILE_EMPTY）。
    "taps": [("stockpile", 0, 0)] * 2,
}

# ---------------- case5: 库存飞生成器（一次）
CASES['case5_stockpile_generator'] = {
    "project": base([lvl("sp_gen", [], [order("o1", CH, [("CleanSet_Ca", 3)])],
        stockpile={"enabled": True, "count": 5, "drop": "generator", "generator": "CleanBox_P",
                   "mode": "sequence",
                   "sequence": [{"entity": "CleanSet_Cj", "level": 2}]})]),
    # 只拍第一次（飞生成器）；第二次应被 SIM_STOCKPILE_SPENT 拒绝，见文字轨迹。
    "taps": [("stockpile", 0, 0)],
}

# ---------------- case7: 库存飞棋子 + 库存自带图标覆盖（操作者 2026-11-13 报的 bug）
# 期望：飞出来的仍是 Ca/Cb/Cc/Cd 自己的图，不能被库存的 C_G 图标盖成"生成器样子"。
CASES['case7_stockpile_chip_icon'] = {
    "project": base([lvl("sp_chip_icon", [], [order("o1", CH, [("CleanSet_Ca", 3)])],
        stockpile={"enabled": True, "count": 5, "drop": "chip", "generator": "CleanBox_P",
                   "mode": "sequence",
                   "sequence": [{"entity": "CleanSet_Ca", "level": 1},
                                {"entity": "CleanSet_Cb", "level": 1},
                                {"entity": "CleanSet_Cc", "level": 1},
                                {"entity": "CleanSet_Cd", "level": 1}],
                   "icon": "CleanSet_Cg", "iconLevel": 9})]),
    "taps": [("stockpile", 0, 0)] * 4,
}

# ---------------- case6: 关卡差异（同一个工程，两关各一套配置）
# 6a：看第 1 关（真随机）
CASES['case6a_level1_random'] = {
    "project": base([
        lvl("lvl_random", [GEN_SLOT(1, 1)], [order("a1", CH, [("CleanSet_Ca", 4)])], number=1),
        lvl("lvl_seq", [GEN_SLOT(4, 1, mode="sequence",
                                 sequence=[{"entity": "CleanSet_Ch", "level": 3},
                                           {"entity": "CleanSet_Cd", "level": 2}])],
            [order("b1", CH, [("CleanSet_Cd", 2)])], number=2),
    ]),
    "taps": [("tap", 1, 1), ("tap", 1, 1), ("tap", 1, 1)],
}

# 6b：第 1 关没有订单 → 立刻可 level_next；进第 2 关看顺序队列（同工程、不同关）
CASES['case6b_level2_sequence'] = {
    "project": base([
        lvl("lvl_empty", [], [], number=1),
        lvl("lvl_seq", [GEN_SLOT(4, 1, mode="sequence",
                                 sequence=[{"entity": "CleanSet_Ch", "level": 3},
                                           {"entity": "CleanSet_Cd", "level": 2}])],
            [order("b1", CH, [("CleanSet_Cd", 2)])], number=2),
    ]),
    "taps": [("level_next", 0, 0), ("tap", 4, 1), ("tap", 4, 1)],
}

for name, spec in CASES.items():
    proj_path = OUT / f"{name}.json"
    proj_path.write_text(json.dumps(spec["project"], ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    timeline = []
    for i, (kind, cx, cy) in enumerate(spec["taps"]):
        at = round(0.7 + i * 0.7, 3)
        if kind == "tap":
            timeline.append({"id": f"e{i}", "channel": "sim", "type": "tap", "at": at,
                             "payload": {"target": {"slot": [cx, cy]}}})
        elif kind == "stockpile":
            timeline.append({"id": f"e{i}", "channel": "sim", "type": "stockpile_tap", "at": at,
                             "payload": {}})
        elif kind == "level_next":
            timeline.append({"id": f"e{i}", "channel": "sim", "type": "level_next", "at": at,
                             "payload": {}})

    duration = round(0.7 + len(spec["taps"]) * 0.7 + 1.2, 2)
    first = spec["taps"][0]
    cursor = [[0, cell_center(first[1], first[2])[0], cell_center(first[1], first[2])[1]],
              [duration, cell_center(first[1], first[2])[0], cell_center(first[1], first[2])[1]]]
    take = {"schema": 1, "fps": 60, "duration": duration, "seed": 7,
            "project": f"res://output/probe/{name}.json",
            "timeline": timeline, "cursor": cursor}
    (OUT / f"{name}.take.json").write_text(json.dumps(take, ensure_ascii=False, indent=2) + '\n',
                                           encoding='utf-8')
    print(f"{name}: taps={len(timeline)} duration={duration}")
