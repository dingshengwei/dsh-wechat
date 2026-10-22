#!/bin/sh
# 拉取上游更新 → 重新构建 → 打成本地包（版本号带 -local）→ 装回 DSH 的 desktop profile。
# 用法：  ~/dsh-wechat/update.sh
#
# 版本号规则：
#   上游发布版     0.46.0            ← 从 npm / GitHub Release 装的
#   本地构建版     0.46.0-local.202610230130   ← 这个脚本打出来的
# 这样在 DSH 的插件列表里一眼能看出手上这份是哪来的。
set -eu

REPO="$HOME/dsh-wechat"
R="/Applications/DeepSeek Harness.app/Contents/Resources/runtime/primary-runtime/dependencies"
DSH="/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh"
GIT=/Library/Developer/CommandLineTools/usr/bin/git

[ -d "$REPO/.git" ] || { echo "找不到 $REPO，先 clone 一次"; exit 1; }
cd "$REPO"

# 仓库要求 Node >= 24，系统里是 23.x，所以用 DSH 自带的 runtime。
export PATH="$R/node/bin:$PATH"

# 上游是原作者仓库；origin 指向你自己的 fork（dingshengwei/dsh-wechat）。
echo "== 1/6 git pull（上游） =="
"$GIT" pull --ff-only upstream main

# 构建脚本里会调用 pnpm，给它一个指向自带 pnpm 的 shim。
SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
printf '#!/bin/sh\nexec "%s/node/bin/node" "%s/pnpm/bin/pnpm.cjs" "$@"\n' "$R" "$R" > "$SHIM/pnpm"
chmod +x "$SHIM/pnpm"
export PATH="$SHIM:$PATH"

echo "== 2/6 pnpm install =="
pnpm install --ignore-scripts

echo "== 3/6 build =="
pnpm run build

echo "== 4/6 打本地版本号 =="
PKG="packages/bundle/package.json"
cp "$PKG" "$SHIM/package.json.orig"
# 万一工作区里的版本号已经被改过，先把 -local 尾巴剥掉，只保留上游版本作为基准。
BASE=$(node -p 'require("./packages/bundle/package.json").version.replace(/-local\..*$/, "")')
STAMP="${BASE}-local.$(date +%Y%m%d%H%M)"
echo "    $BASE  →  $STAMP"
PKG="$PKG" STAMP="$STAMP" node -e '
const fs = require("node:fs");
const p = process.env.PKG;
const d = JSON.parse(fs.readFileSync(p, "utf8"));
d.version = process.env.STAMP;
fs.writeFileSync(p, JSON.stringify(d, null, 2) + "\n");
'

echo "== 5/6 pack =="
node scripts/pack.mjs
# 版本号只用于打这个包，打完立刻还原，别把仓库弄脏。
cp "$SHIM/package.json.orig" "$PKG"

TGZ="$REPO/dsh-wechat-plugin-$STAMP.tgz"
[ -f "$TGZ" ] || { echo "打包产物不存在：$TGZ"; exit 1; }

echo "== 6/6 装进 profile =="
"$DSH" plugin --profile desktop add "$TGZ"

# 只保留最近 3 个 tgz，否则仓库根目录会越堆越多。
ls -t "$REPO"/dsh-wechat-plugin-*.tgz 2>/dev/null | tail -n +4 | while IFS= read -r old; do
  rm -f "$old" && echo "   清理旧包：$(basename "$old")"
done

echo
echo "完成：$TGZ"
echo "装上的版本：$STAMP"
echo "重启 DSH 才生效：菜单栏图标 → 退出，再打开。"
