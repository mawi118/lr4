#!/usr/bin/env bash
# Лабораторная работа №4. Консольный анализ файловой системы преподавателя.
# Используются встроенные средства Bash, grep, sed, sort, find, cut, wc.
set -o pipefail
BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA="$BASE/labfiles-3-26"
SUBJECTS=('Цирковое_Дело' 'Пересдачеведение')
SELECTION=(0 1)

fail() { printf 'Ошибка: %s\n' "$*" >&2; return 1; }
check_data() { [[ -d "$DATA/students/groups" && -d "$DATA/students/general/notes" ]] || fail "Не найдена файловая система: $DATA"; }
valid_group() { [[ "$1" =~ ^[A-Za-z]+-[0-9]{2}-[0-9]{2}$ && -f "$DATA/students/groups/$1" ]]; }
valid_year() { [[ "$1" =~ ^[0-9]{4}$ ]] && ((10#$1 >= 2000 && 10#$1 <= 2099)); }
group_year() { local group=$1 ending=${1##*-}; printf '%d' "$((2000 + 10#$ending + 3))"; }
select_subject() {
    local choice
    printf 'Дисциплина: 1 — Цирковое дело, 2 — Пересдачеведение, 3 — обе: '
    read -r choice || return 1
    case "$choice" in 1) SELECTION=(0);; 2) SELECTION=(1);; 3) SELECTION=(0 1);; *) fail 'Выберите 1, 2 или 3.';; esac
}
ask_group() {
    printf 'Группа (например, A-06-23): '
    read -r GROUP || return 1
    valid_group "$GROUP" || fail "Группа '$GROUP' не найдена."
}
# Список всех попыток из четырёх файлов: поля group;student;date;correct;grade.
# Значения читаются через Bash read, без awk.
collect_tests() {
    local g=$1 s=$2 sub file rec_group rec_student date correct grade
    T_CORRECT=0; T_GRADE_SUM=0; T_COUNT=0
    for sub in "${SELECTION[@]}"; do
        for file in "$DATA/${SUBJECTS[$sub]}/tests/"TEST-*; do
            [[ -f "$file" ]] || continue
            while IFS=';' read -r rec_group rec_student date correct grade || [[ -n "$rec_group" ]]; do
                [[ "$rec_group" == "$g" && "$rec_student" == "$s" ]] || continue
                [[ "$correct" =~ ^[0-9]+$ ]] || continue
                T_CORRECT=$((T_CORRECT + 10#$correct))
                grade_to_quarters "$grade" || continue
                T_GRADE_SUM=$((T_GRADE_SUM + GRADE_Q))
                T_COUNT=$((T_COUNT + 1))
            done < "$file"
        done
    done
}
# Оценка хранится в четвертях балла: 4+ -> 17, 4-- -> 14.
grade_to_quarters() {
    local value=$1 base signs
    [[ "$value" =~ ^([2-5])(\+\+|\+|--|-)?$ ]] || return 1
    base="${BASH_REMATCH[1]}"; signs="${BASH_REMATCH[2]}"
    GRADE_Q=$((base * 4))
    case "$signs" in +) GRADE_Q=$((GRADE_Q+1));; ++) GRADE_Q=$((GRADE_Q+2));; -) GRADE_Q=$((GRADE_Q-1));; --) GRADE_Q=$((GRADE_Q-2));; esac
}
# Процент × 100 (сотые процента), только целочисленная арифметика.
print_percent() { local value=$1 total=$2 p=0; ((total>0)) && p=$((value*10000/total)); printf '%d.%02d%%' "$((p/100))" "$((p%100))"; }
# Средний балл × 100 из суммы четвертей и числа попыток.
print_average() { local qsum=$1 count=$2 scaled=0; ((count>0)) && scaled=$((qsum*25/count)); printf '%d.%02d' "$((scaled/100))" "$((scaled%100))"; }
attendance_one() {
    local g=$1 student=$2 sub=$3 path bits
    ATT_PRESENT=0; ATT_TOTAL=0
    path="$DATA/${SUBJECTS[$sub]}/$g-attendance"
    [[ -f "$path" ]] || return 0
    while read -r name bits || [[ -n "$name" ]]; do
        [[ "$name" == "$student" && "$bits" =~ ^[01]+$ ]] || continue
        local only_ones="${bits//0/}"
        ATT_PRESENT=$((ATT_PRESENT + ${#only_ones}))
        ATT_TOTAL=$((ATT_TOTAL + ${#bits}))
    done < "$path"
}
attendance_all() {
    local g=$1 student=$2 sub
    A_PRESENT=0; A_TOTAL=0
    for sub in "${SELECTION[@]}"; do
        attendance_one "$g" "$student" "$sub"
        A_PRESENT=$((A_PRESENT + ATT_PRESENT))
        A_TOTAL=$((A_TOTAL + ATT_TOTAL))
    done
}
# Год рассчитывается по последним двум цифрам группы + 3.
show_attendance() {
    local from to year student present total best=-1 line group
    printf 'Год начала периода (2000–2099): '; read -r from || return 1
    printf 'Год конца периода (2000–2099): '; read -r to || return 1
    valid_year "$from" && valid_year "$to" && ((10#$from<=10#$to)) || { fail 'Некорректный период.'; return 1; }
    select_subject || return 1
    printf 'Группа (например, A-06-23): '; read -r group || return 1
    valid_group "$group" || { fail 'Группа не найдена.'; return 1; }
    year="$(group_year "$group")"
    if ((year<10#$from || year>10#$to)); then
        printf 'В выбранном периоде у группы %s нет занятий (расчётный год: %s).\n' "$group" "$year"; return 0
    fi
    printf 'Группа %s, расчётный год %s. Посещаемость по выбранным предметам:\n' "$group" "$year"
    local -a leaders=()
    while IFS= read -r student || [[ -n "$student" ]]; do
        attendance_all "$group" "$student"
        ((A_TOTAL>0)) || continue
        # Сравнение долей через перемножение: количество занятий может различаться.
        if ((best<0 || A_PRESENT*best_total>best*A_TOTAL)); then
            best="$A_PRESENT"; best_total="$A_TOTAL"; leaders=("$student")
        elif ((A_PRESENT*best_total==best*A_TOTAL)); then leaders+=("$student"); fi
    done < "$DATA/students/groups/$group"
    if ((${#leaders[@]}==0)); then printf 'Нет данных посещаемости.\n'; return 0; fi
    for student in "${leaders[@]}"; do
        attendance_all "$group" "$student"
        printf '%s — %d/%d (' "$student" "$A_PRESENT" "$A_TOTAL"; print_percent "$A_PRESENT" "$A_TOTAL"; printf ')\n'
    done
}
show_leader() {
    local student max=-1
    ask_group || return 1
    select_subject || return 1
    local -a leaders=()
    while IFS= read -r student || [[ -n "$student" ]]; do
        collect_tests "$GROUP" "$student"
        if ((T_COUNT==0)); then continue; fi
        if ((T_CORRECT>max)); then max="$T_CORRECT"; leaders=("$student")
        elif ((T_CORRECT==max)); then leaders+=("$student"); fi
    done < "$DATA/students/groups/$GROUP"
    if ((${#leaders[@]}==0)); then printf 'Результаты тестирования отсутствуют.\n'; return 0; fi
    printf 'Максимум правильных ответов: %d\n' "$max"
    printf 'Студенты:\n'; printf ' - %s\n' "${leaders[@]}"
}

main() {
    local choice
    check_data || return 1
    while true; do
        printf '\n===== ЛР №4: F1 + F2 =====\n'
        printf '1. Лучшая посещаемость за период\n2. Максимум правильных ответов\n0. Выход\nВыбор: '
        read -r choice || break
        case "$choice" in
            1) show_attendance;;
            2) show_leader;;
            0) break;;
            *) printf 'Введите цифру от 0 до 2.\n';;
        esac
    done
}
main "$@"
