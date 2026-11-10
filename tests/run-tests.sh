#!/usr/bin/env bash
# Проверки F1-F4 на отдельных копиях синтетической файловой системы.
set -u -o pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/tests/data/synthetic/labfiles-3-26"
TEMP="$(mktemp -d /tmp/lr4-qa.XXXXXX)" || exit 2
cleanup() { [[ "$TEMP" == /tmp/lr4-qa.* && -d "$TEMP" ]] && rm -r -- "$TEMP"; }
trap cleanup EXIT
PASS=0 FAIL=0

tree_hash() {
    (cd -- "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}
DATA_HASH="$(tree_hash "$SRC")"
SCRIPT_HASH="$(sha256sum "$ROOT/scripts/lab4.sh" | cut -d' ' -f1)"
error() { BAD=1; printf '  %s\n' "$*" >&2; }
has() { grep -Fq -- "$1" "$OUT" "$ERR" || error "Нет строки: $1"; }
lacks() { grep -Fq -- "$1" "$OUT" "$ERR" && error "Лишняя строка: $1"; }
code_is() { [[ "$CODE" -eq "$1" ]] || error "Код $CODE вместо $1"; }
finish() {
    [[ "$(tree_hash "$BEFORE")" == "$(tree_hash "$WORK/labfiles-3-26")" ]] || error 'Данные изменились'
    if ((BAD)); then
        printf 'FAIL %s\n' "$ID"
        printf '  stdout: %s\n  stderr: %s\n' "$(tail -c 220 "$OUT")" "$(tail -c 220 "$ERR")" >&2
        FAIL=$((FAIL+1))
    else
        printf 'PASS %s\n' "$ID"
        PASS=$((PASS+1))
    fi
}
finish_changed() {
    [[ "$(tree_hash "$BEFORE")" != "$(tree_hash "$WORK/labfiles-3-26")" ]] || error 'Ожидаемое изменение данных не произошло'
    if ((BAD)); then
        printf 'FAIL %s\n' "$ID"
        printf '  stdout: %s\n  stderr: %s\n' "$(tail -c 220 "$OUT")" "$(tail -c 220 "$ERR")" >&2
        FAIL=$((FAIL+1))
    else
        printf 'PASS %s\n' "$ID"
        PASS=$((PASS+1))
    fi
}
file_has() { [[ -f "$WORK/labfiles-3-26/$1" ]] && grep -Fq -- "$2" "$WORK/labfiles-3-26/$1" || error "Нет записи $2 в $1"; }
file_lacks() { [[ -f "$WORK/labfiles-3-26/$1" ]] || { error "Нет файла $1"; return; }; grep -Fq -- "$2" "$WORK/labfiles-3-26/$1" && error "Лишняя запись $2 в $1"; }
file_same() { cmp -s -- "$BEFORE/$1" "$WORK/labfiles-3-26/$1" || error "Изменён $1"; }
no_rank_temp() { [[ -z "$(find "$WORK" -maxdepth 1 -name '.ranking.*' -print)" ]] || error 'Остался временный файл рейтинга'; }
rank_order() {
    local prev=0 name line
    for name in "$@"; do
        line="$(grep -n -m1 -F -- "$name" "$OUT" | cut -d: -f1)"
        [[ -n "$line" && "$line" -gt "$prev" ]] || error "Неверный порядок рейтинга: $name"
        [[ -n "$line" ]] && prev="$line"
    done
}
rank_value() { grep -F -- "$1" "$OUT" | grep -Fq -- "$2 ($3 попыток)" || error "Неверный балл или число попыток: $1"; }
start() {
    ID=$1 INPUT=$2 VARIANT=${3:-normal} BAD=0
    CASE="$(mktemp -d "$TEMP/$ID.XXXXXX")" || exit 2
    WORK="$CASE/work"
    mkdir -p -- "$WORK"
    cp -- "$ROOT/scripts/lab4.sh" "$WORK/lab4.sh" || exit 2
    cp -a -- "$SRC" "$WORK/labfiles-3-26" || exit 2
    [[ "$WORK/labfiles-3-26" != "$ROOT/scripts/labfiles-3-26" && ! -L "$WORK/labfiles-3-26" ]] || exit 2
    case "$VARIANT" in
        normal|other_cwd) ;;
        no_att) rm -- "$WORK/labfiles-3-26/Цирковое_Дело/A-06-23-attendance" "$WORK/labfiles-3-26/Пересдачеведение/A-06-23-attendance" ;;
        bad_att) printf 'PetrovPA 1X1\n' >> "$WORK/labfiles-3-26/Цирковое_Дело/A-06-23-attendance" ;;
        no_lf_att) printf 'TwinTT 11\nOtherOO 1110' > "$WORK/labfiles-3-26/Цирковое_Дело/A-06-24-attendance" ;;
        no_tests) rm -- "$WORK/labfiles-3-26/Цирковое_Дело/tests/TEST-1" "$WORK/labfiles-3-26/Цирковое_Дело/tests/TEST-2" "$WORK/labfiles-3-26/Пересдачеведение/tests/TEST-1" ;;
        bad_count) printf 'A-06-23;IvanovII;2026-01-03;X;5\n' >> "$WORK/labfiles-3-26/Цирковое_Дело/tests/TEST-1" ;;
        bad_grade) printf 'A-06-23;IvanovII;2026-01-03;5;X\n' >> "$WORK/labfiles-3-26/Цирковое_Дело/tests/TEST-1" ;;
        no_lf_test) printf 'A-06-24;TwinTT;2027-01-01;6;4' > "$WORK/labfiles-3-26/Цирковое_Дело/tests/TEST-1" ;;
        no_lf_note) printf '====================\nIvanovII\nЗаметка Иванова.' > "$WORK/labfiles-3-26/students/general/notes/INames.log" ;;
        multiline_note) printf '====================\nSmirnovAA\nПервая строка.\nВторая строка.\n====================\nSmirnovBB\nЗаметка второго Смирнова.\n====================\n' > "$WORK/labfiles-3-26/students/general/notes/SNames.log" ;;
        no_groups) mv -- "$WORK/labfiles-3-26/students/groups" "$WORK/groups-hidden" ;;
        *) printf 'Неизвестный вариант %s\n' "$VARIANT" >&2; exit 2 ;;
    esac
    BEFORE="$CASE/before"
    cp -a -- "$WORK/labfiles-3-26" "$BEFORE"
    OUT="$CASE/stdout" ERR="$CASE/stderr"
    printf '%s' "$INPUT" > "$CASE/stdin"
    if [[ "$VARIANT" == other_cwd ]]; then
        if (cd -- "$CASE" && timeout 10s bash "$WORK/lab4.sh" < "$CASE/stdin" > "$OUT" 2> "$ERR"); then CODE=0; else CODE=$?; fi
    else
        if timeout 10s bash "$WORK/lab4.sh" < "$CASE/stdin" > "$OUT" 2> "$ERR"; then CODE=0; else CODE=$?; fi
    fi
    [[ "$CODE" -ne 124 ]] || error 'Тайм-аут 10 секунд'
}

ID=G-01 BAD=0
bash -n "$ROOT/scripts/lab4.sh" || error 'Синтаксис Bash'
if ((BAD)); then printf 'FAIL %s\n' "$ID"; FAIL=$((FAIL+1)); else printf 'PASS %s\n' "$ID"; PASS=$((PASS+1)); fi
start G-02 $'x\n0\n'; has 'Введите цифру от 0 до 5.'; finish
start G-03 $'0\n'; code_is 0; has '0. Выход'; finish
start G-04 $'0\n' no_groups; has 'Не найдена файловая система'; code_is 1; finish
start G-05 $'2\nA-06-23\n3\n1\n2026\n2026\n3\nA-06-23\n0\n'; has 'Максимум правильных ответов: 12'; has 'IvanovII — 4/6'; finish
start G-06 $'2\nA-06-23\n3\n0\n' other_cwd; has 'Максимум правильных ответов: 12'; finish

start F1-01 $'1\n2026\n2026\n3\nA-06-23\n0\n'; has 'IvanovII — 4/6 (66.66%)'; has 'PetrovPA — 4/6 (66.66%)'; has 'SidorovSS — 4/6 (66.66%)'; lacks 'EmptyEE —'; finish
start F1-02 $'1\n2026\n2026\n1\nA-06-23\n0\n'; has 'PetrovPA — 2/2 (100.00%)'; lacks 'SidorovSS —'; finish
start F1-03 $'1\n2026\n2026\n2\nA-06-23\n0\n'; has 'SidorovSS — 2/2 (100.00%)'; lacks 'PetrovPA —'; finish
start F1-04 $'1\n2025\n2025\n3\nA-06-23\n0\n'; has 'нет занятий (расчётный год: 2026)'; finish
start F1-05 $'1\n2027\n2026\n0\n'; has 'Некорректный период.'; finish
start F1-06 $'1\n1999\n2026\n0\n'; has 'Некорректный период.'; finish
start F1-07 $'1\nabc\n2026\n0\n'; has 'Некорректный период.'; finish
start F1-08 $'1\n2026\n2026\n9\n0\n'; has 'Выберите 1, 2 или 3.'; finish
start F1-09 $'1\n2026\n2026\n3\nA-00-00\n0\n'; has 'Группа не найдена.'; finish
start F1-10 $'1\n2024\n2024\n3\nA-06-21\n0\n'; has 'Нет данных посещаемости.'; finish
start F1-11 $'1\n2027\n2027\n1\nA-06-24\n0\n'; has 'TwinTT — 2/2 (100.00%)'; lacks 'OtherOO —'; finish
start F1-12 $'1\n2026\n2026\n3\nA-06-23\n0\n' no_att; has 'Нет данных посещаемости.'; finish
start F1-13 $'1\n2026\n2026\n1\nA-06-23\n0\n' bad_att; has 'PetrovPA — 2/2 (100.00%)'; finish
start F1-14 $'1\n2027\n2027\n1\nA-06-24\n0\n' no_lf_att; has 'TwinTT — 2/2 (100.00%)'; finish

start F2-01 $'2\nA-06-23\n3\n0\n'; has 'Максимум правильных ответов: 12'; has ' - IvanovII'; has ' - PetrovPA'; has ' - SidorovSS'; lacks ' - EmptyEE'; finish
start F2-02 $'2\nA-06-23\n1\n0\n'; has 'Максимум правильных ответов: 8'; has ' - IvanovII'; finish
start F2-03 $'2\nA-06-23\n2\n0\n'; has 'Максимум правильных ответов: 6'; has ' - SidorovSS'; finish
start F2-04 $'2\nA-06-21\n3\n0\n'; has 'Результаты тестирования отсутствуют.'; finish
start F2-05 $'2\nA-06-23\n3\n0\n' no_tests; has 'Результаты тестирования отсутствуют.'; finish
start F2-06 $'2\nA-06-25\n1\n0\n'; has 'Максимум правильных ответов: 0'; has ' - ZeroZZ'; finish
start F2-07 $'2\nA-06-23\n1\n0\n' bad_count; has 'Максимум правильных ответов: 8'; finish
start F2-08 $'2\nA-06-23\n1\n0\n' bad_grade; has 'Максимум правильных ответов: 13'; finish
start F2-09 $'2\nA-00-00\n3\n0\n'; has "Группа 'A-00-00' не найдена."; finish
start F2-10 $'2\nA-06-24\n1\n0\n' no_lf_test; has 'Максимум правильных ответов: 6'; has ' - TwinTT'; finish
start F2-11 $'2\nA-06-23\n9\n0\n'; has 'Выберите 1, 2 или 3.'; finish
start F2-12 $'2\nA-06-24\n1\n0\n'; has 'Максимум правильных ответов: 3'; has ' - OtherOO'; lacks ' - IvanovII'; finish

start F3-01 $'3\nSmirnov\n1\n1\n0\n'; has 'SmirnovAA — A-06-23'; has 'SmirnovBB — A-06-23'; has 'Заметка первого Смирнова.'; finish
start F3-02 $'3\npEtRoV\n1\n1\n0\n'; has 'PetrovPA — A-06-23'; has 'Заметка Петрова.'; finish
start F3-03 $'3\nPetrovPA\n1\n1\n0\n'; has 'Заметка Петрова.'; finish
start F3-04 $'3\nSmirnov\n2\n1\n0\n'; has 'Заметка второго Смирнова.'; lacks 'Заметка первого Смирнова.'; finish
start F3-05 $'3\nEmptyEE\n1\n1\n0\n'; has 'Заметки отсутствуют.'; finish
start F3-06 $'3\nIvanovII\n1\n2\n0\n'; has 'Студент: IvanovII | группа: A-06-23'; has 'посещаемость: 3/4'; has 'посещаемость: 1/2'; has 'правильные ответы: 8'; has 'правильные ответы: 4'; has 'Заметка Иванова.'; finish
start F3-07 $'3\nNobody\n0\n'; has 'Студент не найден.'; finish
start F3-08 $'3\nSmirnov\n99\n0\n'; has 'Некорректный номер.'; finish
start F3-09 $'3\nSmirnov AA\n0\n'; has 'Введите фамилию латиницей'; finish
start F3-10 $'4\nSmirnovAA\n1\n2\n2\n0\n'; has 'Отменено.'; finish
start F3-11 $'4\nSmirnovAA\n1\n1\n1\n3\nPetrovPA\n1\n1\n0\n'; has 'Удаление выполнено.'; has 'Заметка Петрова.'; file_lacks 'students/general/notes/SNames.log' 'SmirnovAA'; file_has 'students/general/notes/SNames.log' 'SmirnovBB'; file_same 'students/groups/A-06-23'; file_same 'Цирковое_Дело/A-06-23-attendance'; file_same 'Цирковое_Дело/tests/TEST-1'; file_same 'Пересдачеведение/tests/TEST-1'; file_same 'students/general/notes/INames.log'; finish_changed
start F3-12 $'4\nSmirnovAA\n1\n2\n1\n3\nSmirnovBB\n1\n1\n0\n'; has 'Удаление выполнено.'; has 'Заметка второго Смирнова.'; file_lacks 'students/groups/A-06-23' 'SmirnovAA'; file_lacks 'Цирковое_Дело/A-06-23-attendance' 'SmirnovAA'; file_lacks 'Пересдачеведение/A-06-23-attendance' 'SmirnovAA'; file_lacks 'Цирковое_Дело/tests/TEST-1' 'A-06-23;SmirnovAA'; file_lacks 'Пересдачеведение/tests/TEST-1' 'A-06-23;SmirnovAA'; file_lacks 'students/general/notes/SNames.log' 'SmirnovAA'; file_has 'students/general/notes/SNames.log' 'SmirnovBB'; file_has 'students/groups/A-06-23' 'SmirnovBB'; file_has 'Цирковое_Дело/A-06-23-attendance' 'SmirnovBB'; file_has 'Цирковое_Дело/tests/TEST-1' 'A-06-23;SmirnovBB'; file_same 'students/groups/A-06-24'; file_same 'Цирковое_Дело/A-06-24-attendance'; finish_changed
start F3-13 $'4\nIvanovII\n1\n2\n1\n0\n'; has 'Удаление выполнено.'; file_has 'students/groups/A-06-24' 'IvanovII'; file_same 'Цирковое_Дело/A-06-24-attendance'; file_has 'Цирковое_Дело/tests/TEST-1' 'A-06-24;IvanovII'; file_has 'students/general/notes/INames.log' 'IvanovII'; finish_changed
start F3-14 $'4\nSmirnovAA\n1\n2\n1\n2\nA-06-23\n3\n5\nA-06-23\n3\n1\n2026\n2026\n3\nA-06-23\n0\n'; has 'Максимум правильных ответов: 12'; has 'Рейтинг группы A-06-23'; has 'IvanovII — 4/6'; file_lacks 'students/groups/A-06-23' 'SmirnovAA'; no_rank_temp; finish_changed
start F3-15 $'4\nSmirnovAA\n1\n2\n9\n0\n'; has 'Отменено.'; finish
start F3-16 $'3\nIvanovII\n1\n1\n0\n' no_lf_note; has 'Заметка Иванова.'; finish
start F3-17 $'3\nSmirnovAA\n1\n1\n0\n' multiline_note; has 'Первая строка.'; lacks 'Вторая строка.'; finish
start F3-18 $'4\nSmirnovAA\n1\n1\n1\n0\n' multiline_note; file_lacks 'students/general/notes/SNames.log' 'Первая строка.'; file_has 'students/general/notes/SNames.log' 'Вторая строка.'; finish_changed
start F3-19 $'4\nSmirnovAA\n1\n2\n1\n3\nSmirnovAA\n0\n'; has 'Удаление выполнено.'; has 'Студент не найден.'; file_lacks 'students/groups/A-06-23' 'SmirnovAA'; finish_changed

start F4-01 $'5\nA-06-23\n3\n0\n'; rank_order SmirnovBB PetrovPA IvanovII SidorovSS SmirnovAA EmptyEE; rank_value SmirnovBB 4.50 2; rank_value PetrovPA 4.00 2; rank_value IvanovII 3.83 3; rank_value SidorovSS 3.50 2; rank_value SmirnovAA 2.00 2; has 'нет оценок'; no_rank_temp; finish
start F4-02 $'5\nA-06-23\n1\n0\n'; rank_order SmirnovBB IvanovII PetrovPA SidorovSS SmirnovAA EmptyEE; rank_value SmirnovBB 4.50 1; rank_value IvanovII 4.12 2; no_rank_temp; finish
start F4-03 $'5\nA-06-23\n2\n0\n'; rank_order SmirnovBB PetrovPA SidorovSS IvanovII SmirnovAA EmptyEE; rank_value IvanovII 3.25 1; no_rank_temp; finish
start F4-04 $'5\nA-06-21\n3\n0\n'; has 'Рейтинг группы A-06-21'; if awk '/^Рейтинг группы/{seen=1;next} seen && /^$/{exit} seen && /^[[:space:]]*[0-9]+\. /{print}' "$OUT" | grep -q .; then error 'Пустая группа получила строку рейтинга'; fi; no_rank_temp; finish
start F4-05 $'5\nA-06-23\n3\n0\n' no_tests; has 'нет оценок'; no_rank_temp; finish
start F4-06 $'5\nA-00-00\n3\n0\n'; has "Группа 'A-00-00' не найдена."; no_rank_temp; finish
start F4-07 $'5\nA-06-23\n1\n0\n' bad_grade; rank_value IvanovII 4.12 2; no_rank_temp; finish
start F4-08 $'5\nA-06-23\n3\n0\n'; rank_value SmirnovBB 4.50 2; rank_value IvanovII 3.83 3; no_rank_temp; finish

ID=G-07 BAD=0
[[ "$(tree_hash "$SRC")" == "$DATA_HASH" ]] || error 'Исходная синтетическая ФС изменилась'
[[ "$(sha256sum "$ROOT/scripts/lab4.sh" | cut -d' ' -f1)" == "$SCRIPT_HASH" ]] || error 'Исходный скрипт изменился'
if ((BAD)); then printf 'FAIL %s\n' "$ID"; FAIL=$((FAIL+1)); else printf 'PASS %s\n' "$ID"; PASS=$((PASS+1)); fi
printf 'ИТОГО: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
((FAIL==0))
