#!/bin/zsh
# Rebuilds the README visuals (hero.gif, feature-*.gif, banner.png) from the screenshots in docs/screenshots.
# Needs node + puppeteer, ffmpeg and a Chrome. These come with the "repo-visuals" Claude Code skill:
#   PLUGIN=~/.claude/plugins/cache/livlign/repo-visuals/0.1.5   (default)
#   PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"   (if its own Chrome won't start)
# Usage: ./build.sh [OUT=dir] [TARGETS="hero themes chatgpt menubar banner"]
set -euo pipefail
cd "${0:A:h}"
PLUGIN=${PLUGIN:-$HOME/.claude/plugins/cache/livlign/repo-visuals/0.1.5}
CAP=$PLUGIN/skills/repo-visuals/scripts
OUT=${OUT:-..}; TARGETS=${TARGETS:-hero themes chatgpt menubar banner}
mkdir -p assets work "$OUT"; OUT=${OUT:A}

# real app screenshots -> window-only crops (the app window sits at the same place in every shot)
cp ../app-icon.png assets/icon.png
for f in 1-overview 2-reports 3-insights 4-menu-bar 5-light 6-oled 7-chatgpt 8-personalise; do
  ffmpeg -v error -y -i ../screenshots/$f.png -vf "crop=1772:1122:314:334,scale=1880:-1:flags=lanczos" assets/$f.png
done

# gif <name> <html> <ms> <fps> <colours> <out>
gif() {
  rm -rf work/$1; node $CAP/capture.js --html "$PWD/$2" --out work/$1 --manifest work/$1.txt --duration $3 --width 1200 --height 800
  ffmpeg -v error -y -f concat -safe 0 -i work/$1.txt -vf "fps=$4,scale=1200:800:flags=lanczos+accurate_rnd+full_chroma_int,palettegen=stats_mode=full:max_colors=$5" work/$1.png
  ffmpeg -v error -y -f concat -safe 0 -i work/$1.txt -i work/$1.png -lavfi "fps=$4,scale=1200:800:flags=lanczos+accurate_rnd+full_chroma_int [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" -loop 0 "$6"
  ls -la "$6" | awk '{printf "%s  %.1f MB\n", $9, $5/1048576}'
}
feature() { sed "s/__SCENE__/$1/" feature.html > work/feature-$1.html; cp work/feature-$1.html feature-$1.html; }

for t in ${=TARGETS}; do
  case $t in
    hero)    gif hero hero.html 16000 15 192 "$OUT/hero.gif" ;;
    themes)  feature themes;  gif themes  feature-themes.html  14000 12 160 "$OUT/feature-themes.gif" ;;
    chatgpt) feature chatgpt; gif chatgpt feature-chatgpt.html 11000 15 192 "$OUT/feature-chatgpt.gif" ;;
    menubar) feature menubar; gif menubar feature-menubar.html 13000 15 192 "$OUT/feature-menubar.gif" ;;
    banner)  node $CAP/screenshot.js --html "$PWD/banner.html" --out "$OUT/banner.png" --width 1280 --height 640 ;;
  esac
done
rm -f feature-*.html
