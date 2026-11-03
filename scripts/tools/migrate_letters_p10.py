# -*- coding: utf-8 -*-
"""P10.10 / P10.11 / P10.8 信件数据迁移：重排 order、迁移 20 件委托、新增 23 封信、门槛重算、设备解锁信。"""
import os, re, sys

DIR = 'resources/game_data/letters'

ORDER = {
    'window': 1, 'milk_merchant': 5, 'sugar_jar': 6, 'flour_sack': 7,
    'butter_warmth': 9, 'grinder_owner': 10, 'oven_heat': 11,
    'fridge_hum': 13, 'before_leaving': 14,
    'east_asia_arrive': 15, 'east_asia_note': 17, 'east_asia_leave': 19,
    'middle_page': 20, 'beyond_paper': 21,
    'southeast_asia_arrive': 22, 'southeast_asia_note': 24, 'southeast_asia_leave': 26,
    'vegetable_patch': 27, 'rice_sack': 28,
    'south_asia_arrive': 29, 'south_asia_note': 31, 'south_asia_leave': 33,
    'butcher_street': 34,
    'middle_east_arrive': 35, 'middle_east_note': 37, 'middle_east_leave': 39,
    'stove_fire': 40,
    'mediterranean_arrive': 41, 'mediterranean_note': 43, 'mediterranean_leave': 45,
    'steamer_lid': 46,
    'western_arrive': 47, 'western_note': 49, 'western_leave': 51,
    'americas_arrive': 52, 'americas_note': 54, 'americas_leave': 56,
    'africa_arrive': 57, 'africa_note': 59, 'africa_leave': 61,
    'fast_food_arrive': 62, 'fast_food_note': 64, 'fast_food_leave': 66,
    'second_room': 67,
}

CATALOG = {
    'flour_sack': 70, 'fridge_hum': 100, 'before_leaving': 130,
    'east_asia_leave': 353, 'southeast_asia_leave': 386, 'south_asia_leave': 417,
    'middle_east_leave': 451, 'mediterranean_leave': 485, 'western_leave': 518,
    'americas_leave': 550, 'africa_leave': 574, 'fast_food_leave': 602,
    'second_room': 612,
}

STRIP_TASK = ['window', 'oven_heat'] + [
    '%s_%s' % (r, s) for r in ['east_asia', 'southeast_asia', 'south_asia', 'middle_east',
                               'mediterranean', 'western', 'americas', 'africa', 'fast_food']
    for s in ['arrive', 'note']
]

# (order, key, condition, condition_ref, condition_value, rewards, reward_coins, task)
# task = (goal, ref, amount, reward_coins) or None
NEW = [
    (2, 'task_window_1', 1, 'window', 0, [], 0, (1, 'game:item/pour_over', 1, 20)),
    (3, 'coffee_machine', 4, 'task_window_1', 0,
     [('game:item/milk', 1), ('game:item/coffee_bean', 1)], 0, None),
    (5, 'teach_market', 1, 'milk_merchant', 0, [], 0, None),
    (8, 'teach_upgrade', 1, 'flour_sack', 0, [], 0, None),
    (12, 'task_oven_heat_1', 1, 'oven_heat', 0, [], 0, (1, 'game:item/croissant', 1, 40)),
]
REGIONS = [
    ('east_asia', 16, 18), ('southeast_asia', 23, 25), ('south_asia', 30, 32),
    ('middle_east', 36, 38), ('mediterranean', 42, 44), ('western', 48, 50),
    ('americas', 53, 55), ('africa', 58, 60), ('fast_food', 63, 65),
]
for region, arrive_order, note_order in REGIONS:
    NEW.append((arrive_order, 'task_%s_arrive_1' % region, 1, '%s_arrive' % region, 0,
                [], 0, (2, 'game:theme/%s' % region, 2, 60)))
    NEW.append((note_order, 'task_%s_note_1' % region, 1, '%s_note' % region, 0,
                [], 0, (5, '', 2, 50)))
NEW.sort(key=lambda r: r[0])


def key_of(text):
    m = re.search(r'^id = "letter/([a-z_0-9]+)"$', text, re.M)
    return m.group(1) if m else None


def strip_task_fields(text):
    out, skip = [], False
    for line in text.split('\n'):
        if re.match(r'^task_(title|body|goal|ref|amount|reward_coins|rewards) = ', line):
            skip = True
            continue
        if skip and line.strip() == '':
            continue
        skip = False
        out.append(line)
    while out and out[-1].strip() == '':
        out.pop()
    return '\n'.join(out) + '\n'


def set_order(text, order):
    return re.sub(r'^order = \d+$', 'order = %d' % order, text, count=1, flags=re.M)


def set_catalog(text, value):
    return re.sub(r'^condition_value = \d+$', 'condition_value = %d' % value, text, count=1, flags=re.M)


def build(order, key, cond, ref, cond_value, rewards, coins, task):
    lines = ['[gd_resource type="Resource" script_class="LetterDef" format=3]', '']
    lines.append('[ext_resource type="Script" path="res://scripts/resources/material_stack.gd" id="1_stack"]')
    lines.append('[ext_resource type="Script" path="res://scripts/resources/letter_def.gd" id="2_letter"]')
    lines.append('')
    subs = []
    for i, (mat, amount) in enumerate(rewards):
        sid = 'Resource_r%d' % i
        lines.append('[sub_resource type="Resource" id="%s"]' % sid)
        lines.append('script = ExtResource("1_stack")')
        lines.append('material = "%s"' % mat)
        lines.append('amount = %d' % amount)
        lines.append('')
        subs.append(sid)
    lines.append('[resource]')
    lines.append('script = ExtResource("2_letter")')
    lines.append('title = "data.letter.%s.title"' % key)
    lines.append('body = "data.letter.%s.body"' % key)
    lines.append('order = %d' % order)
    lines.append('condition = %d' % cond)
    if cond_value:
        lines.append('condition_value = %d' % cond_value)
    elif ref:
        lines.append('condition_ref = "game:letter/%s"' % ref)
    if rewards:
        refs = ', '.join('SubResource("%s")' % s for s in subs)
        lines.append('rewards = Array[ExtResource("1_stack")]([%s])' % refs)
    if coins:
        lines.append('reward_coins = %d' % coins)
    lines.append('id = "letter/%s"' % key)
    lines.append('display_name = "data.letter.%s.name"' % key)
    lines.append('description = "data.letter.%s.desc"' % key)
    if task:
        goal, tref, amount, trc = task
        lines.append('task_title = "data.letter.%s.task_title"' % key)
        lines.append('task_body = "data.letter.%s.task_body"' % key)
        lines.append('task_goal = %d' % goal)
        if tref:
            lines.append('task_ref = "%s"' % tref)
        lines.append('task_amount = %d' % amount)
        lines.append('task_reward_coins = %d' % trc)
    return '\n'.join(lines) + '\n'


def main():
    existing = {}
    for name in sorted(os.listdir(DIR)):
        if not name.endswith('.tres'):
            continue
        path = os.path.join(DIR, name)
        text = open(path, encoding='utf-8').read()
        key = key_of(text)
        if key:
            existing[key] = (name, text)

    missing = [k for k in ORDER if k not in existing]
    if missing:
        print('!! 缺少旧信:', missing)
        return 1
    extra = [k for k in existing if k not in ORDER]
    if extra:
        print('!! 未规划的旧信:', extra)
        return 1

    for key, order in ORDER.items():
        name, text = existing[key]
        text = set_order(text, order)
        if key in CATALOG:
            text = set_catalog(text, CATALOG[key])
        if key in STRIP_TASK:
            text = strip_task_fields(text)
        new_name = 'letter_%02d_%s.tres' % (order, key)
        os.remove(os.path.join(DIR, name))
        open(os.path.join(DIR, new_name), 'w', encoding='utf-8', newline='\n').write(text)

    for order, key, cond, ref, cond_value, rewards, coins, task in NEW:
        path = os.path.join(DIR, 'letter_task_%s.tres' % key[5:] if key.startswith('task_') else os.path.join(DIR, 'letter_%s.tres' % key))
        if True:
            fname = 'letter_%02d_%s.tres' % (order, key) if not key.startswith('task_') else 'letter_%s.tres' % key
            path = os.path.join(DIR, fname)
        open(path, 'w', encoding='utf-8', newline='\n').write(
            build(order, key, cond, ref, cond_value, rewards, coins, task))

    # 设备解锁信
    fac = [
        ('resources/game_data/facilities/coffee_machine.tres', 'category = "coffee_machine"',
         'unlock_letter = "game:letter/coffee_machine"'),
        ('resources/game_data/facilities/steamer.tres', 'category = "steamer"',
         'unlock_letter = "game:letter/east_asia_arrive"'),
    ]
    for path, anchor, line in fac:
        text = open(path, encoding='utf-8').read()
        if 'unlock_letter' in text:
            print('! 已有 unlock_letter:', path)
            continue
        text = text.replace(anchor + '\n', anchor + '\n' + line + '\n', 1)
        open(path, 'w', encoding='utf-8', newline='\n').write(text)
        print('设备解锁信:', path)

    files = sorted(os.listdir(DIR))
    print('信件文件数:', len(files))
    return 0


sys.exit(main())
