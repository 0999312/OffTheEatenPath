# -*- coding: utf-8 -*-
"""P10.10 / P10.11 / P10.8 i18n 迁移：67 封信重建 data.letter 段、name 编号重排、23 封新文案。"""
import json, re

LOCALES = ['zh_CN', 'en']

ORDER = {
    'window': 1, 'task_window_1': 2, 'coffee_machine': 3, 'milk_merchant': 4,
    'teach_market': 5, 'sugar_jar': 6, 'flour_sack': 7, 'teach_upgrade': 8,
    'butter_warmth': 9, 'grinder_owner': 10, 'oven_heat': 11, 'task_oven_heat_1': 12,
    'fridge_hum': 13, 'before_leaving': 14,
    'east_asia_arrive': 15, 'task_east_asia_arrive_1': 16, 'east_asia_note': 17,
    'task_east_asia_note_1': 18, 'east_asia_leave': 19,
    'middle_page': 20, 'beyond_paper': 21,
    'southeast_asia_arrive': 22, 'task_southeast_asia_arrive_1': 23,
    'southeast_asia_note': 24, 'task_southeast_asia_note_1': 25, 'southeast_asia_leave': 26,
    'vegetable_patch': 27, 'rice_sack': 28,
    'south_asia_arrive': 29, 'task_south_asia_arrive_1': 30, 'south_asia_note': 31,
    'task_south_asia_note_1': 32, 'south_asia_leave': 33,
    'butcher_street': 34,
    'middle_east_arrive': 35, 'task_middle_east_arrive_1': 36, 'middle_east_note': 37,
    'task_middle_east_note_1': 38, 'middle_east_leave': 39,
    'stove_fire': 40,
    'mediterranean_arrive': 41, 'task_mediterranean_arrive_1': 42, 'mediterranean_note': 43,
    'task_mediterranean_note_1': 44, 'mediterranean_leave': 45,
    'steamer_lid': 46,
    'western_arrive': 47, 'task_western_arrive_1': 48, 'western_note': 49,
    'task_western_note_1': 50, 'western_leave': 51,
    'americas_arrive': 52, 'task_americas_arrive_1': 53, 'americas_note': 54,
    'task_americas_note_1': 55, 'americas_leave': 56,
    'africa_arrive': 57, 'task_africa_arrive_1': 58, 'africa_note': 59,
    'task_africa_note_1': 60, 'africa_leave': 61,
    'fast_food_arrive': 62, 'task_fast_food_arrive_1': 63, 'fast_food_note': 64,
    'task_fast_food_note_1': 65, 'fast_food_leave': 66,
    'second_room': 67,
}

STRIP_TASK = ['window', 'oven_heat'] + [
    '%s_%s' % (r, s) for r in ['east_asia', 'southeast_asia', 'south_asia', 'middle_east',
                               'mediterranean', 'western', 'americas', 'africa', 'fast_food']
    for s in ['arrive', 'note']
]

CN_DIGITS = '零一二三四五六七八九'

def cn_num(n):
    if n < 10:
        return CN_DIGITS[n]
    if n < 20:
        return '十' + (CN_DIGITS[n % 10] if n % 10 else '')
    tens, ones = divmod(n, 10)
    return CN_DIGITS[tens] + '十' + (CN_DIGITS[ones] if ones else '')

EN_ONES = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
           'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
           'Seventeen', 'Eighteen', 'Nineteen']
EN_TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty']

def en_num(n):
    if n < 20:
        return EN_ONES[n]
    tens, ones = divmod(n, 10)
    return EN_TENS[tens] + ('-' + EN_ONES[ones] if ones else '')

NEW = {}

NEW['task_window_1'] = {
    'zh': {'title': '第一杯',
           'body': '杯子在架子上，壶也在。\n烧一次水，让豆子从干变湿，味道就出来了。\n做完摆在窗台上，我想看看它冒气的样子。\n——写信的人',
           'desc': '字写在卡片背面，笔迹压得很重。',
           'task_title': '烧一壶水，冲一杯',
           'task_body': '磨一磨，冲一杯滴滤。\n做完就算办妥，报酬放在信封里。'},
    'en': {'title': 'The First Cup',
           'body': "The cup is on the shelf. So is the kettle.\nBoil the water once, let the dry beans go wet, and the smell comes out.\nLeave it on the windowsill when it's done — I want to see it steam.\n— the one who writes",
           'desc': 'The words are written on the back of a card, pressed hard.',
           'task_title': 'Put the kettle on and pour',
           'task_body': "Grind and pour a dripper.\nDone is done; the pay is in the envelope."},
}

NEW['coffee_machine'] = {
    'zh': {'title': '门口的木箱',
           'body': '门口放了个木箱，比我还高一点。\n拆开，是台咖啡机。铜的，擦一擦能照见自己。\n下面压着一瓶牛奶和一袋豆子。\n它以前是我的，现在归你。别让它闲着。\n——写信的人',
           'desc': '信封里夹着一张送货单，边角卷起。'},
    'en': {'title': 'The Crate at the Door',
           'body': "A crate was left at the door, a little taller than me.\nInside is a coffee machine. Brass. Wipe it and you can see yourself.\nUnder it: a bottle of milk and a bag of beans.\nIt was mine once. It's yours now. Don't let it sit idle.\n— the one who writes",
           'desc': 'A delivery note is tucked into the envelope, its corners curled.'},
}

NEW['teach_market'] = {
    'zh': {'title': '推车和坡上的树',
           'body': '你现在能从两个地方拿到东西，别只走一条路。\n推车每天来一趟，车上的东西卖完就要等——想留的，早点买。\n屋子后面那片坡上也长东西，走到跟前伸手就行，不用跟谁商量。\n两条路都走走，台面才不会空。',
           'desc': '信纸背面画着一辆歪歪扭扭的小车。'},
    'en': {'title': 'The Cart and the Hill',
           'body': "You can get things from two places now. Don't walk only one.\nThe cart comes once a day, and when it sells out you wait — buy early if you want it.\nThe slope behind the house grows things too. Walk up and reach; no one to ask.\nUse both, or the counter runs empty.",
           'desc': 'On the back is a crooked little drawing of a cart.'},
}

NEW['teach_upgrade'] = {
    'zh': {'title': '拧紧的螺丝',
           'body': '台面上的家伙用久了会响。\n响的时候别忍着，拆开来，把松的地方拧紧，它就能快一点。\n还有灶台边那块板子——把两样东西摆上去，它能告诉你第三种可能。\n试一次就懂了。',
           'desc': '信封里掉出一小截铜螺丝。'},
    'en': {'title': 'The Loose Screw',
           'body': "The things on the counter start to creak after a while.\nDon't put up with it. Open them up, tighten what's loose, and they go faster.\nAnd that board beside the stove — set two things on it and it shows you a third.\nTry it once and you'll see.",
           'desc': 'A short brass screw falls out of the envelope.'},
}

NEW['task_oven_heat_1'] = {
    'zh': {'title': '第二炉',
           'body': '第一炉是你自己摸出来的。\n再烤一炉吧，这次慢一点，等它自己鼓起来。\n面粉我留在袋子里了，够你试三次。',
           'desc': '信纸上沾着一小块干了的黄油。',
           'task_title': '再烤一份可颂',
           'task_body': '可颂一份。\n做完就算办妥，报酬放在信封里。'},
    'en': {'title': 'The Second Batch',
           'body': "The first batch you figured out yourself.\nBake one more — slower this time, let it rise on its own.\nI left flour in the sack. Enough for three tries.",
           'desc': 'A small dried smear of butter is on the paper.',
           'task_title': 'Bake one more croissant',
           'task_body': "One croissant.\nDone is done; the pay is in the envelope."},
}

ARRIVE = {
    'east_asia': {
        'zh': {'title': '两双筷子',
               'body': '街角有人坐在门槛上吃面。\n他没抬头，只说：你也做两道这里的菜吧，让我闻闻对不对。\n就两道。做多了他吃不完。',
               'desc': '纸上有一道筷子压出来的折痕。',
               'task_title': '做两道东亚餐食',
               'task_body': '两道就行，不用挑最难的。'},
        'en': {'title': 'Two Pairs of Chopsticks',
               'body': "Someone is sitting on the doorstep at the corner, eating noodles.\nHe doesn't look up. He only says: make two dishes from here, let me smell whether they're right.\nJust two. More than that and he can't finish.",
               'desc': 'A chopstick-crease runs across the paper.',
               'task_title': 'Cook two East Asian dishes',
               'task_body': 'Two is enough. No need to pick the hardest.'}},
    'southeast_asia': {
        'zh': {'title': '棚子下的火',
               'body': '雨棚下面生着一小堆火。\n守火的人说，这里的味道要辣，要酸，要有人在旁边等。\n做两道给我看看。',
               'desc': '信纸带着一点潮气。',
               'task_title': '做两道东南亚菜',
               'task_body': '两道，辣的酸的都行。'},
        'en': {'title': 'Fire Under the Awning',
               'body': "A small fire is burning under the rain awning.\nThe one tending it says the taste here needs heat, needs sour, needs someone to wait beside it.\nMake two and show me.",
               'desc': 'The paper is a little damp.',
               'task_title': 'Cook two Southeast Asian dishes',
               'task_body': 'Two. Hot or sour, either is fine.'}},
    'south_asia': {
        'zh': {'title': '手上的颜色',
               'body': '这里的人用手指吃饭。\n手指上沾着姜黄和辣椒的颜色，洗不掉，也不洗。\n做两道，颜色要对。',
               'desc': '信封边角有一小块黄色的印子。',
               'task_title': '做两道南亚菜',
               'task_body': '两道。颜色对了，味道就差不多了。'},
        'en': {'title': 'The Color on Their Hands',
               'body': "People here eat with their fingers.\nTurmeric and chili stain them. It doesn't wash off, and they don't try.\nMake two. The color has to be right.",
               'desc': 'A small yellow stain is on the corner of the envelope.',
               'task_title': 'Cook two South Asian dishes',
               'task_body': 'Two. If the color is right, the taste is close.'}},
    'middle_east': {
        'zh': {'title': '墙下的炉',
               'body': '墙根下埋着一只炉子，火一直没灭。\n面团贴上去，一会儿就鼓起来。\n做两道，我看看你贴得稳不稳。',
               'desc': '信纸边缘被烤得发脆。',
               'task_title': '做两道中东·中亚菜',
               'task_body': '两道。火别太大。'},
        'en': {'title': 'The Oven at the Wall',
               'body': "An oven is buried at the foot of the wall. Its fire has never gone out.\nPress dough against it and it puffs up in a moment.\nMake two. Let's see whether you can press them on steady.",
               'desc': 'The edges of the paper are singed crisp.',
               'task_title': 'Cook two Middle Eastern dishes',
               'task_body': "Two. Don't let the fire get too big."}},
    'mediterranean': {
        'zh': {'title': '晒着的油',
               'body': '屋顶上晒着一排瓶子，油是绿的。\n这里的东西简单：油、盐、火，还有时间。\n做两道，别放太多。',
               'desc': '信封上有一圈油渍。',
               'task_title': '做两道地中海菜',
               'task_body': '两道。油少一点。'},
        'en': {'title': 'Oil Drying in the Sun',
               'body': "A row of bottles is drying on the roof; the oil inside is green.\nThings here are simple: oil, salt, fire, and time.\nMake two. Don't use too much.",
               'desc': 'An oil ring marks the envelope.',
               'task_title': 'Cook two Mediterranean dishes',
               'task_body': 'Two. Easy on the oil.'}},
    'western': {
        'zh': {'title': '一张菜单',
               'body': '墙上的菜单只剩半张。\n剩下的那半写着：趁热。\n做两道，端上来的时候要烫。',
               'desc': '纸很硬，像从菜单上撕下来的。',
               'task_title': '做两道经典西餐',
               'task_body': '两道。上桌要热。'},
        'en': {'title': 'Half a Menu',
               'body': "Only half the menu is left on the wall.\nThe half that remains says: serve hot.\nMake two. They have to be hot when they reach the table.",
               'desc': 'The paper is stiff, like it was torn off a menu.',
               'task_title': 'Cook two classic Western dishes',
               'task_body': 'Two. Hot when served.'}},
    'americas': {
        'zh': {'title': '直路上的车',
               'body': '一条路笔直地穿过去，看不见弯。\n车里的收音机在响，没人关。\n做两道，分量大一点。',
               'desc': '信封上有一道轮胎碾过的灰印。',
               'task_title': '做两道美洲菜',
               'task_body': '两道。多给一点。'},
        'en': {'title': 'The Car on the Straight Road',
               'body': "A road runs straight through, without a bend in sight.\nA radio is playing in a car. Nobody turns it off.\nMake two. Bigger portions.",
               'desc': 'A tire track of grey dust crosses the envelope.',
               'task_title': 'Cook two American dishes',
               'task_body': 'Two. Give a little more.'}},
    'africa': {
        'zh': {'title': '日落很慢',
               'body': '这里的太阳落得很慢。\n慢到锅里的东西能炖透，慢到人愿意坐下来等。\n做两道，别急。',
               'desc': '信纸被晒得发黄。',
               'task_title': '做两道非洲菜',
               'task_body': '两道。慢一点没关系。'},
        'en': {'title': 'The Sun Sets Slowly',
               'body': "The sun goes down slowly here.\nSlow enough for a pot to finish stewing, slow enough for people to sit and wait.\nMake two. No rush.",
               'desc': 'The paper has yellowed in the sun.',
               'task_title': 'Cook two African dishes',
               'task_body': 'Two. Slow is fine.'}},
    'fast_food': {
        'zh': {'title': '最后一家',
               'body': '路到头了。\n最后一家店亮着灯，柜台后面没人。\n做两道，趁灯还亮。',
               'desc': '信封上印着一个褪色的商标。',
               'task_title': '做两道西式快餐',
               'task_body': '两道。快一点。'},
        'en': {'title': 'The Last Shop',
               'body': "The road ends here.\nThe last shop still has its light on. There's no one behind the counter.\nMake two, while the light is still on.",
               'desc': 'A faded logo is printed on the envelope.',
               'task_title': 'Cook two fast food dishes',
               'task_body': 'Two. Quick.'}},
}

NOTE = {
    'east_asia': {
        'zh': {'title': '门口的三行字',
               'body': '门槛上那张纸又出现了。\n这次多了一行：做好了送到门口。\n订单接两张，交出去。',
               'desc': '纸角被踩过一个鞋印。',
               'task_title': '交两张订单',
               'task_body': '门口有人等着。交两张就够。'},
        'en': {'title': 'Three Lines on the Step',
               'body': "That paper on the doorstep is back.\nThis time there's an extra line: when it's done, bring it to the door.\nTake two orders and deliver them.",
               'desc': 'A shoe print sits on one corner.',
               'task_title': 'Deliver two orders',
               'task_body': 'Someone is waiting outside. Two will do.'}},
    'southeast_asia': {
        'zh': {'title': '湿布上的字',
               'body': '一块湿布压在窗台上，上面用炭写着字。\n字快化了，只认出「两张」。\n接两张订单，交出去。',
               'desc': '布已经干了一半，字还在。',
               'task_title': '交两张订单',
               'task_body': '别让人等太久。'},
        'en': {'title': 'Writing on a Wet Cloth',
               'body': "A wet cloth is pressed on the windowsill, words written on it in charcoal.\nThe words are nearly washed away. All I can read is “two”.\nTake two orders and deliver them.",
               'desc': 'The cloth is half dry; the words remain.',
               'task_title': 'Deliver two orders',
               'task_body': "Don't keep anyone waiting too long."}},
    'south_asia': {
        'zh': {'title': '香料袋上的口信',
               'body': '香料袋上系着一根绳，绳上穿着一张纸片。\n纸片上写：两张。\n没别的了。',
               'desc': '纸片上有桂皮的味道。',
               'task_title': '交两张订单',
               'task_body': '两张，交到门口。'},
        'en': {'title': 'A Note on the Spice Sack',
               'body': "A string is tied around the spice sack, and a slip of paper is threaded on it.\nThe slip says: two.\nNothing else.",
               'desc': 'The slip smells of cinnamon.',
               'task_title': 'Deliver two orders',
               'task_body': 'Two, to the door.'}},
    'middle_east': {
        'zh': {'title': '墙根下的单子',
               'body': '墙根下压着一叠单子，最上面那张写着：两张。\n底下那叠是空的。\n接两张，交出去。',
               'desc': '单子边缘被沙磨毛了。',
               'task_title': '交两张订单',
               'task_body': '两张，别弄丢。'},
        'en': {'title': 'The Slip at the Wall',
               'body': "A stack of slips is pressed under the wall. The top one says: two.\nThe rest of the stack is blank.\nTake two and deliver them.",
               'desc': 'Sand has frayed the edge of the slip.',
               'task_title': 'Deliver two orders',
               'task_body': "Two. Don't lose them."}},
    'mediterranean': {
        'zh': {'title': '油瓶旁的纸条',
               'body': '油瓶旁边立着一张纸条。\n上面写着：两张，趁热。\n我把纸条压回去了。',
               'desc': '纸条上有一个油指印。',
               'task_title': '交两张订单',
               'task_body': '两张，趁热交出去。'},
        'en': {'title': 'The Note by the Oil Bottle',
               'body': "A note stands beside the oil bottle.\nIt says: two, while they're hot.\nI put the note back.",
               'desc': 'An oily fingerprint is on the note.',
               'task_title': 'Deliver two orders',
               'task_body': "Two, delivered hot."}},
    'western': {
        'zh': {'title': '柜台上的餐牌',
               'body': '柜台上的餐牌翻到了背面。\n背面用粉笔写：两张。\n粉笔灰落了一台面。',
               'desc': '餐牌上有一道擦不掉的旧字。',
               'task_title': '交两张订单',
               'task_body': '两张，端稳了再走。'},
        'en': {'title': 'The Menu Board on the Counter',
               'body': "The menu board on the counter has been flipped to its back.\nChalk on the back says: two.\nChalk dust has fallen all over the counter.",
               'desc': 'An old word is still there, impossible to wipe off.',
               'task_title': 'Deliver two orders',
               'task_body': 'Two. Steady hands before you go.'}},
    'americas': {
        'zh': {'title': '车窗里的手',
               'body': '车停在路边，车窗摇下来一半。\n一只手伸出来，比了两根手指。\n我猜是两张订单的意思。',
               'desc': '信封上有一道油墨指印。',
               'task_title': '交两张订单',
               'task_body': '两张，送到车边。'},
        'en': {'title': 'A Hand in the Car Window',
               'body': "The car is parked at the roadside, its window rolled halfway down.\nA hand comes out and holds up two fingers.\nI'm guessing that means two orders.",
               'desc': 'An ink fingerprint marks the envelope.',
               'task_title': 'Deliver two orders',
               'task_body': 'Two, to the car.'}},
    'africa': {
        'zh': {'title': '慢下来的钟',
               'body': '墙上的钟停过一次，又走了。\n停在两点，走起来还是两点。\n有人要两张订单，说不用急。',
               'desc': '信封很轻，里面只有一张纸。',
               'task_title': '交两张订单',
               'task_body': '两张。不用跑。'},
        'en': {'title': 'The Clock That Slowed',
               'body': "The clock on the wall stopped once, then started again.\nIt stopped at two; it still says two now.\nSomeone wants two orders, and says there's no hurry.",
               'desc': 'The envelope is light; only one sheet inside.',
               'task_title': 'Deliver two orders',
               'task_body': 'Two. No need to run.'}},
    'fast_food': {
        'zh': {'title': '打烊前的两单',
               'body': '灯要关了。\n柜台后面终于有人说话：最后两张。\n交完这两张，今天的路就到头了。',
               'desc': '信封上有一个油点。',
               'task_title': '交最后两张订单',
               'task_body': '两张。交完就收工。'},
        'en': {'title': 'Two Before Closing',
               'body': "The light is about to go off.\nFinally someone speaks from behind the counter: two more, the last ones.\nDeliver these two, and today's road is done.",
               'desc': 'An oil spot is on the envelope.',
               'task_title': 'Deliver the last two orders',
               'task_body': "Two. Then we're done."}},
}

for region, texts in ARRIVE.items():
    NEW['task_%s_arrive_1' % region] = texts
for region, texts in NOTE.items():
    NEW['task_%s_note_1' % region] = texts


def dump_block(seg):
    keys = sorted(seg, key=lambda k: ORDER[k])
    out = ['\t\t"letter": {']
    for i, k in enumerate(keys):
        out.append('\t\t\t"%s": {' % k)
        fields = [f for f in ['title', 'body', 'name', 'desc', 'task_title', 'task_body'] if f in seg[k]]
        for j, f in enumerate(fields):
            val = json.dumps(seg[k][f], ensure_ascii=False)
            out.append('\t\t\t\t"%s": %s%s' % (f, val, ',' if j < len(fields) - 1 else ''))
        out.append('\t\t\t}%s' % (',' if i < len(keys) - 1 else ''))
    return out


def main():
    for loc in LOCALES:
        path = 'resources/i18n/%s.json' % loc
        lines = open(path, encoding='utf-8').read().split('\n')
        start = end = None
        seg = None
        for i, l in enumerate(lines):
            if l != '\t\t"letter": {':
                continue
            candidate_end = None
            for j in range(i + 1, len(lines)):
                if lines[j] == '\t\t},':
                    candidate_end = j
                    break
            if candidate_end is None:
                continue
            try:
                candidate = json.loads('{' + '\n'.join(lines[i + 1:candidate_end]) + '}')
            except Exception:
                continue
            if 'window' in candidate and 'title' in candidate['window']:
                start, end, seg = i, candidate_end, candidate
                break
        if seg is None:
            print('!! 未找到 data.letter 段:', path)
            return 1
        if len(seg) != 44:
            print('!! 旧信件数不是 44:', len(seg))

        for k in STRIP_TASK:
            seg[k].pop('task_title', None)
            seg[k].pop('task_body', None)

        lang = 'zh' if loc == 'zh_CN' else 'en'
        for k, texts in NEW.items():
            entry = {'title': texts[lang]['title'], 'body': texts[lang]['body'],
                     'name': '占位 · ' + texts[lang]['title'], 'desc': texts[lang]['desc']}
            if 'task_title' in texts[lang]:
                entry['task_title'] = texts[lang]['task_title']
                entry['task_body'] = texts[lang]['task_body']
            seg[k] = entry

        missing_order = [k for k in seg if k not in ORDER]
        if missing_order:
            print('!! 未规划 order 的信:', missing_order)
            return 1

        for k, entry in seg.items():
            name = entry.get('name', '')
            m = re.match(r'^(第.+?封信|Letter .+?) · (.+)$', name)
            if m:
                rest = m.group(2)
            elif name.startswith('占位 · '):
                rest = name[len('占位 · '):]
            else:
                print('!! name 格式异常:', k, '->', name)
                return 1
            if loc == 'zh_CN':
                prefix = '第%s封信' % cn_num(ORDER[k])
            else:
                prefix = 'Letter %s' % en_num(ORDER[k])
            entry['name'] = '%s · %s' % (prefix, rest)

        block = dump_block(seg)
        out = lines[:start] + block + lines[end:]
        text = '\n'.join(out)
        data = json.loads(text)
        if len(data['data']['letter']) != 67:
            print('!! 输出信件数不是 67:', len(data['data']['letter']))
            return 1
        open(path, 'w', encoding='utf-8', newline='\n').write(text)
        print('%s: 67 封, 行 %d -> %d' % (path, len(lines), len(out)))
    return 0


raise SystemExit(main())
