"""自造图标覆盖探针：生成两份只差 icon 字段的工程 + 一条 stockpile_tap 的 take。

输出：
  output/probe/icon_project.json      带 icon / iconLevel
  output/probe/icon_project_plain.json 同样的关卡但去掉 icon（对照组）
  output/probe/icon.take.json         1.0s 点一次库存，时长 3s
"""
import json
from pathlib import Path

SRC = Path('03_Game_ds/data/sample_project.json')
OUT = Path('03_Game_ds/output/probe')
OUT.mkdir(parents=True, exist_ok=True)

base = json.loads(SRC.read_text(encoding='utf-8'))

def make(with_icons: bool) -> dict:
    p = json.loads(json.dumps(base))
    p['meta']['title'] = 'Icon probe' + ('' if with_icons else ' (plain)')
    lv = p['levels'][0]
    lv['id'] = 'icon_probe'
    lv['board'] = {
        'width': 7,
        'height': 9,
        'slots': [
            # 生成器 + 图标覆盖（C_A 第 5 级）
            {'x': 1, 'y': 1, 'entity': 'CleanBox_C', 'level': 1},
            # 参照棋子：同样的图标覆盖，用于像素对拍
            {'x': 3, 'y': 1, 'entity': 'CleanSet_Cb', 'level': 1},
            # 一枚普通棋子，保证合并/订单有东西可看
            {'x': 5, 'y': 1, 'entity': 'CleanSet_Ca', 'level': 1},
        ],
    }
    if with_icons:
        lv['board']['slots'][0].update(icon='CleanSet_Ca', iconLevel=5)
        lv['board']['slots'][1].update(icon='CleanSet_Ca', iconLevel=5)
    lv['obstacles'] = []
    lv['safes'] = []
    lv['stockpile'] = {'enabled': True, 'count': 1, 'generator': 'CleanBox_P'}
    if with_icons:
        lv['stockpile'].update(icon='CleanSet_Ce', iconLevel=4)
    lv['orders'] = [{
        'id': 'o1', 'character': 'char_x' if 'char_x' in p['characters'] else next(iter(p['characters'])),
        'coin': 5, 'gem': 0, 'energy': 0,
        'mission': [{'entity': 'CleanSet_Ca', 'level': 1, 'count': 1}],
    }]
    p['levels'] = [lv]
    p['timeline'] = []
    return p

icon = make(True)
plain = make(False)
(OUT / 'icon_project.json').write_text(json.dumps(icon, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(OUT / 'icon_project_plain.json').write_text(json.dumps(plain, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

take = {
    'schema': 1, 'fps': 60, 'duration': 3.0, 'seed': 7,
    'project': 'res://output/probe/icon_project.json',
    'timeline': [
        {'id': 'e1', 'channel': 'sim', 'type': 'stockpile_tap', 'at': 1.0, 'payload': {}},
    ],
    'cursor': [[0, 300, 260], [3, 300, 260]],
}
(OUT / 'icon.take.json').write_text(json.dumps(take, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('probe written:', OUT / 'icon_project.json', OUT / 'icon_project_plain.json', OUT / 'icon.take.json')
