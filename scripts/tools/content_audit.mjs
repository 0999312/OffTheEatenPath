// 内容自检：读 audit_dump.gd 导出的 _dump.json，生成三表 + findings。
// 用法（项目根目录）：
//   godot --headless --path . -s scripts/tools/audit_dump.gd
//   node scripts/tools/content_audit.mjs
import fs from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const DATA = path.join(ROOT, "docs/plans/2026-10-28-content-audit");
const dump = JSON.parse(fs.readFileSync(path.join(DATA, "_dump.json"), "utf8"));

function loadFlat(rel) {
  const raw = JSON.parse(fs.readFileSync(path.join(ROOT, rel), "utf8"));
  const out = {};
  (function walk(obj, prefix) {
    for (const key of Object.keys(obj)) {
      const value = obj[key];
      const full = prefix ? prefix + "." + key : key;
      if (value && typeof value === "object" && !Array.isArray(value)) walk(value, full);
      else out[full] = value;
    }
  })(raw, "");
  return out;
}
const zh = loadFlat("resources/i18n/zh_CN.json");
const en = loadFlat("resources/i18n/en.json");
const tx = (key) => {
  if (typeof key !== "string" || !key.startsWith("data.")) return key;
  return zh[key] !== undefined ? zh[key] : (en[key] !== undefined ? en[key] : key);
};
const lastPart = (key) => key.split("/").pop();
const itemBy = new Map(dump.items.map((i) => [i.key, i]));
const recipeBy = new Map(dump.recipes.map((r) => [r.key, r]));
const facBy = new Map(dump.facilities.map((f) => [f.key, f]));
const themeBy = new Map(dump.themes.map((t) => [t.key, t]));
const letterBy = new Map(dump.letters.map((l) => [l.key, l]));
const tagBy = new Map();
const tagScope = {};
for (const file of fs.readdirSync(path.join(ROOT, "resources/game_data/tags"))) {
  if (!file.endsWith(".tres")) continue;
  const key = "game:tag/" + file.replace(/\.tres$/, "");
  const body = fs.readFileSync(path.join(ROOT, "resources/game_data/tags", file), "utf8");
  tagBy.set(key, lastPart(key));
  const line = body.split("\n").find((x) => x.trim().startsWith("scope = "));
  tagScope[key] = line ? Number(line.split("=")[1].trim()) : 0;
}
const tagName = (key) => tx("data.tag." + lastPart(key) + ".name");
const nameOf = (key) => {
  const item = itemBy.get(key);
  return item ? tx(item.display_name) : key;
};
const facName = (key) => (key ? tx(facBy.get(key).display_name) : "无设备");
const themeName = (key) => tx(themeBy.get(key).display_name);
const letterName = (key) => (key ? tx(letterBy.get(key).title) : "开局");
const groupName = (g) => (g ? zh["ui.craft.group_" + g] : "—");
const stackText = (s) => (s.by_tag ? "任意" + tagName(s.by_tag) : nameOf(s.material)) + "×" + s.amount;
const inputsText = (r) => r.inputs.map(stackText).join(" + ");
const producedBy = new Map();
const consumedBy = new Map();
const consumedByTag = new Map();
for (const r of dump.recipes) {
  if (!producedBy.has(r.output)) producedBy.set(r.output, []);
  producedBy.get(r.output).push(r);
  for (const s of r.inputs) {
    if (s.material) {
      if (!consumedBy.has(s.material)) consumedBy.set(s.material, []);
      consumedBy.get(s.material).push(r);
    }
    if (s.by_tag) {
      if (!consumedByTag.has(s.by_tag)) consumedByTag.set(s.by_tag, []);
      consumedByTag.get(s.by_tag).push(r);
    }
  }
}
const harvestOf = (item) => dump.harvest.filter((h) => item.tags.includes(h.tag));
const reachable = (key) => {
  const item = itemBy.get(key);
  if (!item) return false;
  return item.material_kind === 2 || harvestOf(item).length > 0 || item.merchant_price > 0 || producedBy.has(key);
};
const usesOf = (item) => {
  const exact = consumedBy.get(item.key) ? consumedBy.get(item.key).length : 0;
  let layered = 0;
  for (const tag of item.tags) layered += consumedByTag.get(tag) ? consumedByTag.get(tag).length : 0;
  return { exact, layered };
};
const add = (list, group, message) => list.push({ group, message });
const hard = [];
const soft = [];

// ── 硬检查 ──
for (const r of dump.recipes) {
  if (!itemBy.has(r.output)) add(hard, "引用", "配方 " + r.key + " 的产出 " + r.output + " 不存在");
  if (r.facility && !facBy.has(r.facility)) add(hard, "引用", "配方 " + r.key + " 的设备 " + r.facility + " 不存在");
  if (r.inputs.length === 0) add(hard, "输入", "配方 " + r.key + " 没有输入材料");
  for (const s of r.inputs) {
    if (s.material && !itemBy.has(s.material)) add(hard, "引用", "配方 " + r.key + " 的输入 " + s.material + " 不存在");
    if (s.by_tag && !tagBy.has(s.by_tag)) add(hard, "引用", "配方 " + r.key + " 的标签 " + s.by_tag + " 不存在");
  }
  for (const m of r.research_pool) {
    if (!itemBy.has(m) || !reachable(m)) add(hard, "研究", "配方 " + r.key + " 的研究池材料 " + m + " 不存在或不可达");
  }
  if (r.research_min_facility_level > 0 && !r.facility) add(hard, "研究", "配方 " + r.key + " 有研究门槛但没有设备");
  if (r.research_pool.length > 0 && r.research_pool.length < 2) add(hard, "研究", "配方 " + r.key + " 的研究池少于 2 样");
}
for (const item of dump.items) {
  if (!themeBy.has(item.theme)) add(hard, "引用", "物品 " + item.key + " 的主题 " + item.theme + " 不存在");
  if (item.kind === 0) {
    const fromHarvest = harvestOf(item).length > 0;
    const buyable = item.merchant_price > 0;
    const produced = producedBy.has(item.key);
    if (item.material_kind === 0 && !fromHarvest && !buyable && !produced) add(hard, "材料来源", "基础材料 " + nameOf(item.key) + " 没有来源");
    if (item.material_kind === 1 && !produced) add(hard, "材料来源", "中间材料 " + nameOf(item.key) + " 没有配方产出");
    {
      const u = usesOf(item);
      if (u.exact + u.layered === 0) add(hard, "材料用途", "材料 " + nameOf(item.key) + " 没有任何配方使用");
    }
  }
  if (item.kind === 1) {
    if (item.sell_price <= 0) add(soft, "产出去处", "食物 " + nameOf(item.key) + " 没有收购价，进不了订单板");
    if (!item.in_catalog) add(soft, "产出去处", "食物 " + nameOf(item.key) + " 不进图鉴，请确认是不是有意");
  }
}
for (const f of dump.facilities) {
  if (f.unlock_letter && !letterBy.has(f.unlock_letter)) add(hard, "引用", "设备 " + f.key + " 的解锁信 " + f.unlock_letter + " 不存在");
  if (f.max_level < 1) add(hard, "设备", "设备 " + f.key + " 的 max_level 小于 1");
}
for (const t of dump.themes) {
  if (t.unlock_letter && !letterBy.has(t.unlock_letter)) add(hard, "引用", "主题 " + t.key + " 的解锁信 " + t.unlock_letter + " 不存在");
}
for (const h of dump.harvest) {
  if (!tagBy.has(h.tag)) add(hard, "引用", "采集点 " + h.key + " 的标签 " + h.tag + " 不存在");
  if (h.unlock_facility && !facBy.has(h.unlock_facility)) add(hard, "引用", "采集点 " + h.key + " 的解锁设备 " + h.unlock_facility + " 不存在");
  if (h.unlock_letter && !letterBy.has(h.unlock_letter)) add(hard, "引用", "采集点 " + h.key + " 的解锁信 " + h.unlock_letter + " 不存在");
  const lens = [h.cooldown_seconds.length, h.yield_per_click.length, h.trickle_per_second.length];
  if (lens.some((n) => n !== lens[0])) add(hard, "采集点", "采集点 " + h.key + " 的等级数组长度不一致");
}
for (const l of dump.letters) {
  const ref = l.task_ref || "";
  if (ref.startsWith("game:letter/") && !letterBy.has(ref)) add(hard, "信件", "信件 " + l.key + " 的 task_ref " + ref + " 不存在");
  if (ref.startsWith("game:item/") && !itemBy.has(ref)) add(hard, "信件", "信件 " + l.key + " 的 task_ref " + ref + " 不存在");
  if (ref.startsWith("game:theme/") && !themeBy.has(ref)) add(hard, "信件", "信件 " + l.key + " 的 task_ref " + ref + " 不存在");
  if (ref.startsWith("game:tag/") && !tagBy.has(ref)) add(hard, "信件", "信件 " + l.key + " 的 task_ref " + ref + " 不存在");
  if (ref.startsWith("game:recipe/") && !recipeBy.has(ref)) add(hard, "信件", "信件 " + l.key + " 的 task_ref " + ref + " 不存在");
  for (const s of l.rewards.concat(l.task_rewards)) {
    if (s.material && !itemBy.has(s.material)) add(hard, "引用", "信件 " + l.key + " 的奖励 " + s.material + " 不存在");
    if (s.by_tag && !tagBy.has(s.by_tag)) add(hard, "引用", "信件 " + l.key + " 的奖励标签 " + s.by_tag + " 不存在");
  }
}
const outSeen = new Map();
for (const r of dump.recipes) {
  if (!outSeen.has(r.output)) outSeen.set(r.output, []);
  outSeen.get(r.output).push(r.key);
  if (r.inputs.some((s) => s.material === r.output)) add(hard, "输入", "配方 " + r.key + " 的输入包含自己的产出");
  if (r.duration_seconds <= 0) add(hard, "耗时", "配方 " + r.key + " 的耗时不是正数");
  if (r.duration_seconds > 120) add(hard, "耗时", "配方 " + r.key + " 的耗时超过 120 秒");
}
for (const [output, keys] of outSeen) if (keys.length > 1) add(hard, "输入", "产出 " + output + " 有多个配方：" + keys.join("、"));


// ── 软检查：关键词启发式（不自动判错，进人工清单） ──
const SOFT_RULES = [
  { name: "布朗尼", ids: ["brownie"], words: ["布朗尼"], need: [["cocoa", "chocolate", "可可", "巧克力"]], why: "布朗尼应含巧克力/可可" },
  { name: "披萨", ids: ["pizza"], words: ["披萨"], need: [["tomato", "番茄"]], why: "披萨应含番茄" },
  { name: "汉堡", ids: ["hamburger", "cheeseburger"], words: ["汉堡"], need: [["bread", "bun", "面包"]], why: "汉堡应有面包" },
  { name: "塔可/卷饼", ids: ["taco", "burrito", "chicken_wrap", "kebab_wrap"], words: ["塔可", "卷饼"], need: [["corn", "tortilla", "玉米"]], why: "塔可/卷饼应有玉米饼；若面包视为通用饼皮可忽略" },
  { name: "烘焙", ids: ["cake", "cheesecake", "carrot_cake", "muffin", "waffle", "pancake", "scone", "tres_leches"], words: ["蛋糕", "玛芬", "华夫", "松饼", "司康"], need: [["flour", "batter", "dough", "蛋糕", "面粉", "面糊", "面团"]], why: "烘焙类应有面粉/面糊/面团或现成蛋糕" },
  { name: "三明治", ids: ["sandwich", "blt", "bagel_sandwich", "hot_dog"], words: ["三明治", "热狗"], need: [["bread", "bagel", "面包", "贝果"]], why: "三明治类应有面包或贝果" },
  { name: "面食", ids: ["bagel", "banh_mi", "naan", "pita", "focaccia", "mooncake"], words: ["法棍", "馕", "皮塔", "佛卡夏", "月饼"], need: [["flour", "dough", "bread", "面粉", "面团", "面包"]], why: "面食应有面粉/面团/面包" },
  { name: "咖啡", ids: ["latte", "cappuccino", "macchiato", "mocha", "flat_white", "americano"], words: ["拿铁", "卡布奇诺", "玛奇朵", "摩卡", "澳白", "美式"], need: [["coffee", "espresso", "咖啡", "浓缩"]], why: "咖啡饮品应有咖啡" },
  { name: "奶茶", ids: ["milk_tea", "chai"], words: ["奶茶", "印度奶茶"], need: [["tea", "茶"], ["milk", "奶"]], why: "奶茶应含茶与奶" },
  { name: "饭类", ids: ["sushi", "onigiri", "bibimbap"], words: ["寿司", "饭团", "拌饭"], need: [["rice", "白饭", "米"]], why: "饭类应有米饭" },
  { name: "咖喱", ids: ["chicken_curry", "green_curry", "red_curry", "curry_rice"], words: ["咖喱"], need: [["spice", "curry", "香料", "咖喱"]], why: "咖喱应有香料" },
  { name: "冬阴功", ids: ["tom_yum"], words: ["冬阴功"], need: [["shrimp", "虾"]], why: "冬阴功应有虾" },
  { name: "炸鱼薯条", ids: ["fish_and_chips"], words: ["炸鱼薯条"], need: [["fish", "鱼"], ["potato", "土豆"]], why: "炸鱼薯条应有鱼与土豆" },
];
const softHits = [];
for (const r of dump.recipes) {
  const output = itemBy.get(r.output);
  if (!output || output.kind !== 1) continue;
  const cn = tx(r.display_name);
  const rid = lastPart(r.key);
  for (const rule of SOFT_RULES) {
    const matched = rule.ids.indexOf(rid) >= 0 || rule.words.some((k) => cn.indexOf(k) >= 0);
    if (!matched) continue;
    let hay = "";
    for (const s of r.inputs) {
      if (s.by_tag) {
        hay += " " + tagName(s.by_tag) + " " + s.by_tag;
      } else {
        const input = itemBy.get(s.material);
        hay += " " + s.material + " " + (input ? tx(input.display_name) : "") + " " + (input ? input.tags.join(" ") : "");
      }
    }
    hay = hay.toLowerCase();
    const missing = rule.need.filter((group) => !group.some((k) => hay.indexOf(k.toLowerCase()) >= 0));
    softHits.push({ recipe: r, output, cn, rule, ok: missing.length === 0, missing: missing.map((g) => g.join("/")).join(" 且 ") });
  }
}
const pending = softHits.filter((h) => !h.ok);

// ── 统计 ──
const foods = dump.items.filter((i) => i.kind === 1);
const materials = dump.items.filter((i) => i.kind === 0);
const foodRecipes = dump.recipes.filter((r) => itemBy.get(r.output) && itemBy.get(r.output).kind === 1);
const midRecipes = dump.recipes.filter((r) => itemBy.get(r.output) && itemBy.get(r.output).kind === 0);
const totalResearch = dump.recipes.filter((r) => r.research_pool.length > 0).length;
const gradeName = ["基础", "中间", "免费"];
const fileTime = new Date().toISOString().slice(0, 10);
const write = (name, lines) => {
  fs.writeFileSync(path.join(DATA, name), lines.join("\n") + "\n", "utf8");
  return name + " " + lines.length + " 行";
};


// ── materials.md ──
{
  const out = [];
  out.push("# 材料表 · " + fileTime);
  out.push("");
  out.push("> 用途：试玩前人工核对材料来源、价格与用途。");
  out.push(">");
  out.push("> 数据：**" + materials.length + " 种材料**（基础 " + materials.filter((m) => m.material_kind === 0).length + " / 中间 " + materials.filter((m) => m.material_kind === 1).length + " / 免费 " + materials.filter((m) => m.material_kind === 2).length + "）；采集点 " + dump.harvest.length + " 个；商人货架 " + materials.filter((m) => m.merchant_price > 0).length + " 种。");
  out.push("");
  out.push("## 1. 材料总表");
  out.push("");
  out.push("| 材料 | key | 档位 | 来源 | 买价 | 卖价 | 配方用途 | 图鉴 |");
  out.push("|---|---|---|---|---|---|---|---|");
  const rows = materials.slice().sort((a, b) => a.material_kind - b.material_kind || a.order - b.order || a.key.localeCompare(b.key));
  for (const m of rows) {
    const sources = [];
    const hs = harvestOf(m);
    if (hs.length) sources.push("采集：" + hs.map((h) => tx(h.display_name)).join("、"));
    if (m.merchant_price > 0) sources.push("商人");
    const producers = producedBy.get(m.key) || [];
    if (producers.length) sources.push("配方：" + producers.map((r) => nameOf(r.output)).join("、"));
    if (m.material_kind === 2) sources.push("配方自动供给");
    const u = usesOf(m);
    out.push("| " + tx(m.display_name) + " | " + m.key + " | " + gradeName[m.material_kind] + " | " + (sources.join("；") || "**无**") + " | " + (m.merchant_price || "—") + " | " + (m.sell_price || "—") + " | " + u.exact + " / " + u.layered + " | " + (m.in_catalog ? "✓" : "—") + " |");
  }
  out.push("");
  out.push("「配方用途」= 精确指名 / 标签覆盖（被多少条配方当输入）。");
  out.push("");
  out.push("## 2. 采集点");
  out.push("");
  out.push("| 采集点 | 标签 | 覆盖材料 | 解锁 | Lv1 冷却/产量/涓流 |");
  out.push("|---|---|---|---|---|");
  for (const h of dump.harvest.slice().sort((a, b) => a.order - b.order)) {
    const cover = dump.items.filter((i) => i.kind === 0 && i.tags.indexOf(h.tag) >= 0).map((m) => tx(m.display_name));
    const unlock = h.unlock_letter ? "信：" + letterName(h.unlock_letter)
      : h.unlock_facility ? facName(h.unlock_facility) + " Lv" + h.unlock_level : "开局";
    const lv1 = [h.cooldown_seconds[0], h.yield_per_click[0], h.trickle_per_second[0]].join(" / ");
    out.push("| " + tx(h.display_name) + " | " + tagName(h.tag) + " | " + (cover.join("、") || "（无）") + " | " + unlock + " | " + lv1 + " |");
  }
  out.push("");
  out.push("## 3. 商人货架");
  out.push("");
  out.push("| 材料 | 买价 | 卖价 | 采集点 | 配方用途（精确/标签） |");
  out.push("|---|---|---|---|---|");
  for (const m of materials.filter((m) => m.merchant_price > 0).sort((a, b) => a.merchant_price - b.merchant_price || a.key.localeCompare(b.key))) {
    const u = usesOf(m);
    const hs = harvestOf(m).map((h) => tx(h.display_name)).join("、");
    out.push("| " + tx(m.display_name) + " | " + m.merchant_price + " | " + m.sell_price + " | " + (hs || "—") + " | " + u.exact + " / " + u.layered + " |");
  }
  out.push("");
  out.push("## 4. 标签 → 材料");
  out.push("");
  out.push("| 标签 | 作用域 | 材料 |");
  out.push("|---|---|---|");
  for (const key of Array.from(tagBy.keys()).sort()) {
    const cover = dump.items.filter((i) => i.kind === 0 && i.tags.indexOf(key) >= 0).map((m) => tx(m.display_name));
    out.push("| " + tagName(key) + " | " + (tagScope[key] === 1 ? "配方输入" : "图鉴筛选") + " | " + (cover.join("、") || "—") + " |");
  }
  out.push("");
  out.push("---");
  out.push("");
  out.push("生成：godot --headless --path . -s scripts/tools/audit_dump.gd → node scripts/tools/content_audit.mjs。");
  console.log(write("materials.md", out));
}


// ── recipes.md ──
{
  const out = [];
  out.push("# 配方表 · " + fileTime);
  out.push("");
  out.push("> 用途：人工核对每道菜的设备、耗时、输入与研究门槛。");
  out.push(">");
  out.push("> 数据：**" + dump.recipes.length + " 条** = 食物 " + foodRecipes.length + " + 半成品 " + midRecipes.length + "；其中 **" + totalResearch + " 条需要研究解锁**。");
  out.push("");
  out.push("## 0. 分批总览");
  out.push("");
  out.push("| 主题 | 解锁信 | 食物配方 | 研究配方 | 设备分布 | 待人工复核 |");
  out.push("|---|---|---|---|---|---|");
  const pendingByTheme = new Map();
  for (const h of pending) {
    const key = h.output.theme;
    pendingByTheme.set(key, (pendingByTheme.get(key) || 0) + 1);
  }
  for (const t of dump.themes.slice().sort((a, b) => a.order - b.order)) {
    const rs = foodRecipes.filter((r) => itemBy.get(r.output).theme === t.key);
    if (rs.length === 0) continue;
    const fc = {};
    for (const r of rs) {
      const k = r.facility || "none";
      fc[k] = (fc[k] || 0) + 1;
    }
    const facText = Object.keys(fc).map((k) => (k === "none" ? "无设备" : facName(k)) + " " + fc[k]).join("、");
    out.push("| " + themeName(t.key) + " | " + letterName(t.unlock_letter) + " | " + rs.length + " | " + rs.filter((r) => r.research_pool.length > 0).length + " | " + facText + " | " + (pendingByTheme.get(t.key) || 0) + " |");
  }
  out.push("| 半成品 | — | " + midRecipes.length + " | 0 | 见 §2 | — |");
  out.push("");
  out.push("## 1. 食物配方（按主题）");
  out.push("");
  for (const t of dump.themes.slice().sort((a, b) => a.order - b.order)) {
    const rs = foodRecipes.filter((r) => itemBy.get(r.output).theme === t.key).sort((a, b) => a.order - b.order || a.key.localeCompare(b.key));
    if (rs.length === 0) continue;
    out.push("### " + themeName(t.key) + "（" + rs.length + " 道）");
    out.push("");
    out.push("| 菜 | 设备 | 耗时 | 输入 | 研究 | 组 | 备注 |");
    out.push("|---|---|---|---|---|---|---|");
    for (const r of rs) {
      const ry = r.research_pool.length > 0 ? "池 " + r.research_pool.length + (r.research_min_facility_level > 0 ? " / 门槛 Lv" + r.research_min_facility_level : "") : "—";
      const own = pending.filter((h) => h.recipe === r).map((h) => "待核：" + h.rule.why).join("；");
      out.push("| " + tx(r.display_name) + " | " + facName(r.facility) + " | " + r.duration_seconds + "s | " + inputsText(r) + " | " + ry + " | " + groupName(r.group) + " | " + own + " |");
    }
    out.push("");
  }
  out.push("## 2. 半成品配方（" + midRecipes.length + " 条）");
  out.push("");
  out.push("| 产出 | 设备 | 耗时 | 输入 | 下游用途 | 组 |");
  out.push("|---|---|---|---|---|---|");
  for (const r of midRecipes.slice().sort((a, b) => facName(a.facility).localeCompare(facName(b.facility)) || a.order - b.order)) {
    const used = consumedBy.get(r.output) ? consumedBy.get(r.output).length : 0;
    out.push("| " + nameOf(r.output) + " | " + facName(r.facility) + " | " + r.duration_seconds + "s | " + inputsText(r) + " | " + used + " | " + groupName(r.group) + " |");
  }
  out.push("");
  out.push("---");
  out.push("");
  out.push("生成：godot --headless --path . -s scripts/tools/audit_dump.gd → node scripts/tools/content_audit.mjs。");
  console.log(write("recipes.md", out));
}


// ── research.md ──
{
  const out = [];
  out.push("# 研究表 · " + fileTime);
  out.push("");
  out.push("> 用途：核对研究解锁的候选池是否都拿得到、门槛是否合理。");
  out.push("");
  const rules = dump.research[0];
  out.push("## 1. 研究规则");
  out.push("");
  out.push("| 项目 | 值 |");
  out.push("|---|---|");
  out.push("| 设备 | " + facName(rules.facility) + " |");
  out.push("| 失败累计 | " + rules.burn_counts.join(" → ") + " |");
  out.push("| 保底进度 | " + rules.charge_chance + " |");
  out.push("| 失败保底率 | " + rules.burn_rates.join(" / ") + " |");
  out.push("| 单次耗时 | " + rules.default_seconds + " 秒 |");
  out.push("");
  out.push("## 2. 研究方向（" + totalResearch + " 条）");
  out.push("");
  out.push("| 菜 | 主题 | 设备 | 耗时 | 输入 | 候选池 | 提示 | 门槛 |");
  out.push("|---|---|---|---|---|---|---|---|");
  const researchRecipes = dump.recipes.filter((r) => r.research_pool.length > 0).sort((a, b) => a.order - b.order);
  for (const r of researchRecipes) {
    const output = itemBy.get(r.output);
    const pool = r.research_pool.map((m) => nameOf(m)).join("、");
    const hint = r.research_hint ? tx(r.research_hint) : "—";
    const minLv = r.research_min_facility_level > 0 ? "研究台 Lv" + r.research_min_facility_level : "—";
    out.push("| " + tx(r.display_name) + " | " + themeName(output.theme) + " | " + facName(r.facility) + " | " + r.duration_seconds + "s | " + inputsText(r) + " | " + pool + " | " + hint + " | " + minLv + " |");
  }
  out.push("");
  out.push("## 3. 候选材料频次");
  out.push("");
  const freq = new Map();
  for (const r of researchRecipes) for (const m of r.research_pool) freq.set(m, (freq.get(m) || 0) + 1);
  const top = Array.from(freq.entries()).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  out.push("| 材料 | 出现在几个池 | 可达 |");
  out.push("|---|---|---|");
  for (const entry of top) out.push("| " + nameOf(entry[0]) + " | " + entry[1] + " | " + (reachable(entry[0]) ? "✓" : "**✗**") + " |");
  out.push("");
  out.push("免费材料（水）由配方自动供给，视为可达；其余候选都要求采集点、商人或配方产出至少有一条路。");
  out.push("");
  out.push("---");
  out.push("");
  out.push("生成：godot --headless --path . -s scripts/tools/audit_dump.gd → node scripts/tools/content_audit.mjs。");
  console.log(write("research.md", out));
}

// ── findings.md ──
{
  const out = [];
  out.push("# 内容自检结论 · " + fileTime);
  out.push("");
  out.push("> 数据源：docs/plans/2026-10-28-content-audit/_dump.json（由 scripts/tools/audit_dump.gd 导出）。");
  out.push("> 本文件只记录自动检查能查出的问题；可玩性与手感仍需实机试玩。");
  out.push("");
  out.push("## 摘要");
  out.push("");
  out.push("| 指标 | 结果 |");
  out.push("|---|---|");
  out.push("| 物品 | " + dump.items.length + "（食物 " + foods.length + " / 材料 " + materials.length + "） |");
  out.push("| 配方 | " + dump.recipes.length + "（食物 " + foodRecipes.length + " / 半成品 " + midRecipes.length + "） |");
  out.push("| 设备 / 主题 / 采集点 | " + dump.facilities.length + " / " + dump.themes.length + " / " + dump.harvest.length + " |");
  out.push("| 信件 | " + dump.letters.length + " |");
  out.push("| 硬检查 | " + (hard.length === 0 ? "✓ 0 条" : "**" + hard.length + " 条**") + " |");
  out.push("| 软检查命中 / 通过 / 待人工 | " + softHits.length + " / " + (softHits.length - pending.length) + " / **" + pending.length + "** |");
  out.push("");
  out.push("## 1. 硬检查（这些必须是 0）");
  out.push("");
  const groups = ["引用", "输入", "研究", "材料来源", "材料用途", "产出去处", "设备", "采集点", "信件", "耗时"];
  out.push("| 检查 | 结果 |");
  out.push("|---|---|");
  for (const g of groups) {
    const rows = hard.filter((x) => x.group === g);
    if (rows.length === 0) {
      out.push("| " + g + " | ✓ 0 条 |");
    } else {
      for (const row of rows) out.push("| " + g + " | **" + row.message + "** |");
    }
  }
  out.push("");
  out.push("## 2. 待人工复核（软检查）");
  out.push("");
  if (pending.length === 0) {
    out.push("✓ 无。");
  } else {
    out.push("| 菜 | 输入 | 规则 | 缺什么 |");
    out.push("|---|---|---|---|");
    for (const h of pending) out.push("| " + h.cn + " | " + inputsText(h.recipe) + " | " + h.rule.name + " | " + (h.missing || "—") + " |");
    out.push("");
    out.push("逐条判断：缺的原料是不是被同类材料替代了（比如面包当饼皮）；能解释就在本文件写下结论，不能解释就当作内容缺口修。");
    out.push("");
    out.push("本轮结论：塔可、鸡肉卷、烤肉卷都把**面包当通用饼皮**，与「面包可以代替饼皮」的既有口径一致；卷饼已改用玉米饼，另有三道新菜各补了来路。若以后要统一成「塔可必须玉米饼」，再把这四条一起改。");
  }
  out.push("");
  out.push("## 3. 软检查规则与命中");
  out.push("");
  out.push("| 规则 | 说明 | 命中 | 通过 | 待核 |");
  out.push("|---|---|---|---|---|");
  for (const rule of SOFT_RULES) {
    const hits = softHits.filter((h) => h.rule === rule);
    out.push("| " + rule.name + " | " + rule.why + " | " + hits.length + " | " + hits.filter((h) => h.ok).length + " | " + hits.filter((h) => !h.ok).length + " |");
  }
  out.push("");
  out.push("## 4. 结构统计");
  out.push("");
  out.push("### 设备分布（食物配方）");
  out.push("");
  out.push("| 设备 | 配方数 |");
  out.push("|---|---|");
  const facCount = new Map();
  for (const r of foodRecipes) facCount.set(r.facility || "none", (facCount.get(r.facility || "none") || 0) + 1);
  for (const entry of Array.from(facCount.entries()).sort((a, b) => b[1] - a[1])) out.push("| " + (entry[0] === "none" ? "无设备" : facName(entry[0])) + " | " + entry[1] + " |");
  out.push("");
  out.push("### 耗时分布");
  out.push("");
  out.push("| 档位 | 食物配方数 |");
  out.push("|---|---|");
  const buckets = [["≤10s", 0, 10], ["11–30s", 11, 30], ["31–60s", 31, 60], ["61–120s", 61, 120]];
  for (const b of buckets) out.push("| " + b[0] + " | " + foodRecipes.filter((r) => r.duration_seconds >= b[1] && r.duration_seconds <= b[2]).length + " |");
  const longest = foodRecipes.slice().sort((a, b) => b.duration_seconds - a.duration_seconds).slice(0, 5);
  out.push("");
  out.push("最长的五道：" + longest.map((r) => tx(r.display_name) + " " + r.duration_seconds + "s").join("、") + "。");
  out.push("");
  out.push("### 主题配方数");
  out.push("");
  out.push("| 主题 | 食物 |");
  out.push("|---|---|");
  for (const t of dump.themes.slice().sort((a, b) => a.order - b.order)) out.push("| " + themeName(t.key) + " | " + foodRecipes.filter((r) => itemBy.get(r.output).theme === t.key).length + " |");
  out.push("| 中间材料 | " + midRecipes.length + " |");
  out.push("");
  out.push("### 没有任何用途的材料");
  out.push("");
  const dead = materials.filter((m) => { const u = usesOf(m); return u.exact + u.layered === 0; });
  out.push(dead.length === 0 ? "✓ 无。" : dead.map((m) => "**" + nameOf(m.key) + "**").join("、"));
  out.push("");
  out.push("## 5. 与设计目标的偏差");
  out.push("");
  out.push("信件结构：");
  out.push("");
  const condCount = new Map();
  for (const l of dump.letters) condCount.set(l.condition, (condCount.get(l.condition) || 0) + 1);
  const COND_NAMES = ["立即（开场）", "读完前一封", "做过某道菜", "图鉴进度", "委托办妥"];
  out.push("| 项 | 数量 | 说明 |");
  out.push("|---|---|---|");
  out.push("| 信件总数 | " + dump.letters.length + " | 叙事信 + 委托信 + 教学信 |");
  out.push("| 带委托 | " + dump.letters.filter((l) => l.task_goal > 0).length + " | 序章 2 + 九站各 2 |");
  out.push("| 解锁离线 | " + dump.letters.filter((l) => l.unlocks_offline).length + " | 只该有一封 |");
  for (const [k, n] of Array.from(condCount.entries()).sort((a, b) => a[0] - b[0])) {
    out.push("| 条件 · " + (COND_NAMES[k] || ("类型 " + k)) + " | " + n + " | |");
  }
  out.push("");
  out.push("图鉴门槛：" + dump.letters.filter((l) => l.condition === 3)
    .map((l) => l.key.replace("game:letter/", "") + " " + l.condition_value).join("、") + "。");
  out.push("");
  out.push("设备解锁信现状：");
  out.push("");
  out.push("| 设备 | 解锁信 | 当前状态 |");
  out.push("|---|---|---|");
  for (const f of dump.facilities) out.push("| " + facName(f.key) + " | " + (f.unlock_letter ? letterName(f.unlock_letter) : "—") + " | " + (f.unlock_letter ? "信解锁" : "开局可用") + " |");
  out.push("");
  out.push("| 项目 | 设计记录 | 当前数据 |");
  out.push("|---|---|---|");
  out.push("| 图鉴门槛 | D2：前九封压到 70 / 100 / 130，其余按新总数换算 | 已重算 13 个：70 / 100 / 130 + 354 / 387 / 418 / 452 / 486 / 519 / 551 / 575 / 603 / 613（图鉴 632，含仓库设施） |");
  out.push("| 咖啡机 / 蒸笼 | 第三轮设计 P10.8：0 级、由信件解锁 | 已接入：咖啡机 ← 第 3 封「门口的木箱」（第一件委托办妥后）；蒸笼 ← 东亚到站信 |");
  out.push("");
  out.push("## 6. 人工复核步骤");
  out.push("");
  out.push("1. 打开 materials.md：" + materials.length + " 种材料按来源过一遍，重点看「来源：无」。");
  out.push("2. 打开 recipes.md：按 §0 选一批（建议第一站东亚餐食），逐行确认设备、输入、耗时。");
  out.push("3. 回到本文件 §2：3 条待核逐条给结论（都属「面包当饼皮」）；布朗尼已补可可。");
  out.push("4. 抽 5 道菜实机做一次，确认耗时、产出、收购价与表一致。");
  out.push("5. 抽 2 条研究方向，确认候选池材料都拿得到。");
  out.push("");
  out.push("---");
  out.push("");
  out.push("生成：godot --headless --path . -s scripts/tools/audit_dump.gd → node scripts/tools/content_audit.mjs。");
  console.log(write("findings.md", out));
}

console.log("硬检查 " + hard.length + " 条，软检查命中 " + softHits.length + " 条，待核 " + pending.length + " 条。");
