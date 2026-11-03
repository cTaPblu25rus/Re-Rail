#!/usr/bin/env bash
# Собирает рекламный трейлер RE-RAIL из сцен настоящей игры.
# Использование: tools/make_trailer.sh <путь-к-godot> <папка-вывода>
# Нужны: Godot 4.3, ffmpeg, виртуальный или настоящий дисплей (xvfb-run).
set -euo pipefail
GODOT="$1"
OUT="$2"
FPS=30
mkdir -p "$OUT/shots"
cd "$(dirname "$0")/.."

# имя | длительность (с) | аргументы
SHOTS=(
	"01|2.6|--shot=title --text=Десять лет назад мир накрыл|Пепельный занавес"
	"02|3.2|--shot=drive --chapter=0"
	"03|2.2|--shot=title --text=Но сквозь помехи|пробился её голос"
	"04|3.6|--shot=radio --chapter=0"
	"05|2.0|--shot=title --text=Он пройдёт всю магистраль"
	"06|3.0|--shot=station --chapter=0"
	"07|1.3|--shot=title --text=Сквозь туман"
	"08|3.8|--shot=fight --chapter=0"
	"09|1.3|--shot=title --text=Сквозь ржавчину"
	"10|3.0|--shot=packers --chapter=1"
	"11|1.3|--shot=title --text=Сквозь тьму"
	"12|3.4|--shot=crawler --chapter=2"
	"13|1.3|--shot=title --text=Сквозь холод"
	"14|3.0|--shot=snow --chapter=3"
	"15|2.4|--shot=title --text=Дрезина — его дом.|Пёс — его друг."
	"16|3.2|--shot=interior --chapter=2"
	"17|4.5|--shot=title --big --text=RE-RAIL|Хроники Пепла|Скоро на Android"
)

TOTAL=0
LIST="$OUT/shots/list.txt"
: > "$LIST"
for entry in "${SHOTS[@]}"; do
	IFS='|' read -r name len rest <<< "$entry"
	# в тексте титров '|' — перенос строки: склеиваем хвост обратно
	args="${entry#*|*|}"
	dir="$OUT/shots/$name"
	echo "file '$dir/clip.mp4'" >> "$LIST"
	TOTAL=$(python3 -c "print($TOTAL+$len)")
	# ONLY="04 06" — переснять только эти сцены, остальные взять готовыми
	if [[ -n "${ONLY:-}" && " $ONLY " != *" $name "* && -f "$dir/clip.mp4" ]]; then
		continue
	fi
	rm -rf "$dir"; mkdir -p "$dir"
	frames=$(python3 -c "print(int(round($len*$FPS)))")
	echo ">> сцена $name ($len с): $args"
	# аргументы для титров передаём как один (с пробелами внутри)
	if [[ "$args" == *"--text="* ]]; then
		pre="${args%%--text=*}"
		txt="${args#*--text=}"
		# shellcheck disable=SC2086
		xvfb-run -a -s "-screen 0 1400x800x24" "$GODOT" --path . --rendering-driver opengl3 \
			--resolution 1280x720 --write-movie "$dir/f.png" --fixed-fps $FPS --quit-after "$frames" \
			-- $pre "--text=$txt" "--len=$len" > "$dir/log.txt" 2>&1 || true
	else
		# shellcheck disable=SC2086
		xvfb-run -a -s "-screen 0 1400x800x24" "$GODOT" --path . --rendering-driver opengl3 \
			--resolution 1280x720 --write-movie "$dir/f.png" --fixed-fps $FPS --quit-after "$frames" \
			-- $args "--len=$len" > "$dir/log.txt" 2>&1 || true
	fi
	ffmpeg -loglevel error -y -framerate $FPS -i "$dir/f%08d.png" -i "$dir/f.wav" \
		-t "$len" -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 18 \
		-c:a aac -ar 48000 -ac 2 -b:a 160k -shortest "$dir/clip.mp4"
done

echo ">> музыкальная подложка ($TOTAL с)"
mdir="$OUT/shots/music"
mframes=$(python3 -c "print(int(round(($TOTAL+4)*$FPS)))")
if [[ -z "${ONLY:-}" || ! -f "$mdir/f.wav" ]]; then
rm -rf "$mdir"; mkdir -p "$mdir"
xvfb-run -a -s "-screen 0 1400x800x24" "$GODOT" --path . --rendering-driver opengl3 \
	--resolution 320x180 --write-movie "$mdir/f.png" --fixed-fps $FPS --quit-after "$mframes" \
	-- --shot=music --chapter=0 "--len=$TOTAL" > "$mdir/log.txt" 2>&1 || true
fi

echo ">> сборка"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$LIST" -c copy "$OUT/shots/scenes.mp4"
# музыка стартует через 2.5 с (пока синтезируется), поэтому берём её с 3-й секунды
ffmpeg -loglevel error -y -i "$OUT/shots/scenes.mp4" -ss 3 -i "$mdir/f.wav" \
	-filter_complex "[1:a]volume=1.5,afade=t=in:d=1.5,afade=t=out:st=$(python3 -c "print($TOTAL-2.5)"):d=2.5[m];[0:a]volume=1.0[s];[s][m]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]" \
	-map 0:v -map "[a]" -vf "scale=1280:720:flags=neighbor" -c:v libx264 -pix_fmt yuv420p -preset slow -crf 18 \
	-c:a aac -b:a 192k -movflags +faststart "$OUT/re-rail-trailer.mp4"
echo ">> готово: $OUT/re-rail-trailer.mp4 ($TOTAL с)"
