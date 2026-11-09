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
# Заметки: разделители из '=' + пробелы; следующая строка — ID студента.
show_note() {
    local wanted=$1 file line state=0 found=1
    for file in "$DATA/students/general/notes/"*Names.log; do
        [[ -f "$file" ]] || continue
        state=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[=[:space:]]+$ && "$line" == *'='* ]]; then state=1; continue; fi
            if ((state==1)); then
                if [[ "$line" == "$wanted" ]]; then state=2; found=0; else state=0; fi
            elif ((state==2)); then
                printf '%s\n' "$line"
                state=0
            fi
        done < "$file"
    done
    return "$found"
}
# При удалении заметки сохраняем записи других студентов.
remove_notes() {
    local target=$1 file line state tmp name next
    for file in "$DATA/students/general/notes/"*Names.log; do
        [[ -f "$file" ]] || continue
        tmp="$file.tmp.$$"; : > "$tmp" || return 1
        state=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[=[:space:]]+$ && "$line" == *'='* ]]; then
                state=1; printf '%s\n' "$line" >> "$tmp"; continue
            fi
            if ((state==1)); then
                if [[ "$line" == "$target" ]]; then
                    # Удаляем идентификатор и следующую строку текста. Разделители остаются.
                    state=3
                    # Убираем только что записанный разделитель из результата.
                    sed '$d' "$tmp" > "$tmp.next" && mv -- "$tmp.next" "$tmp" || return 1
                    continue
                fi
                state=0
            elif ((state==3)); then
                state=0
                continue
            fi
            printf '%s\n' "$line" >> "$tmp"
        done < "$file"
        mv -- "$tmp" "$file" || return 1
    done
}
# Отбрасываем записи конкретного студента, оставляя других без изменений.
remove_from_group() {
    local g=$1 student=$2 path="$DATA/students/groups/$1" tmp
    tmp="$path.tmp.$$"
    grep -Fvx -- "$student" "$path" > "$tmp" || [[ $? -eq 1 ]] || return 1
    mv -- "$tmp" "$path"
}
remove_from_attendance() {
    local g=$1 student=$2 sub path tmp name bits
    for sub in 0 1; do
        path="$DATA/${SUBJECTS[$sub]}/$g-attendance"
        [[ -f "$path" ]] || continue
        tmp="$path.tmp.$$"; : > "$tmp" || return 1
        while read -r name bits || [[ -n "$name" ]]; do
            [[ "$name" == "$student" ]] || printf '%s %s\n' "$name" "$bits" >> "$tmp"
        done < "$path"
        mv -- "$tmp" "$path" || return 1
    done
}
remove_from_tests() {
    local g=$1 student=$2 sub file tmp line rec_group rec_student rest
    for sub in 0 1; do
        for file in "$DATA/${SUBJECTS[$sub]}/tests/"TEST-*; do
            [[ -f "$file" ]] || continue
            tmp="$file.tmp.$$"; : > "$tmp" || return 1
            while IFS= read -r line || [[ -n "$line" ]]; do
                IFS=';' read -r rec_group rec_student rest <<< "$line"
                [[ "$rec_group" == "$g" && "$rec_student" == "$student" ]] || printf '%s\n' "$line" >> "$tmp"
            done < "$file"
            mv -- "$tmp" "$file" || return 1
        done
    done
}
# Поиск по идентификатору или фамилии без учёта регистра (без регулярных выражений).
find_students() {
    local query=$1 file student group lower_query lower_student
    MATCH_GROUPS=(); MATCH_STUDENTS=()
    lower_query="${query,,}"
    for file in "$DATA/students/groups/"*; do
        [[ -f "$file" ]] || continue
        group="${file##*/}"
        while IFS= read -r student || [[ -n "$student" ]]; do
            lower_student="${student,,}"
            if [[ "$lower_student" == "$lower_query" || "$lower_student" == "$lower_query"[a-z]* ]]; then
                MATCH_GROUPS+=("$group")
                MATCH_STUDENTS+=("$student")
            fi
        done < "$file"
    done
}
choose_student() {
    local query i answer
    printf 'Фамилия или полный идентификатор: '
    read -r query || return 1
    [[ "$query" =~ ^[[:alpha:]]+$ ]] || { fail 'Введите фамилию латиницей (без пробелов).'; return 1; }
    find_students "$query"
    ((${#MATCH_STUDENTS[@]}>0)) || { fail 'Студент не найден.'; return 1; }
    printf 'Найденные студенты:\n'
    for ((i=0;i<${#MATCH_STUDENTS[@]};i++)); do printf '%d) %s — %s\n' "$((i+1))" "${MATCH_STUDENTS[$i]}" "${MATCH_GROUPS[$i]}"; done
    printf 'Номер: '; read -r answer || return 1
    [[ "$answer" =~ ^[0-9]+$ ]] && ((10#$answer>=1 && 10#$answer<=${#MATCH_STUDENTS[@]})) || { fail 'Некорректный номер.'; return 1; }
    STUDENT="${MATCH_STUDENTS[$((10#$answer-1))]}"
    GROUP="${MATCH_GROUPS[$((10#$answer-1))]}"
}
show_dossier() {
    local mode sub
    choose_student || return 1
    printf '1 — только заметки, 2 — полное досье: '; read -r mode || return 1
    case "$mode" in 1|2);; *) fail 'Неверный вариант.'; return 1;; esac
    printf '\nСтудент: %s | группа: %s\n' "$STUDENT" "$GROUP"
    if [[ "$mode" == 2 ]]; then
        for sub in 0 1; do
            SELECTION=("$sub")
            attendance_all "$GROUP" "$STUDENT"
            collect_tests "$GROUP" "$STUDENT"
            printf 'Предмет: %s | посещаемость: %s/%s (' "${SUBJECTS[$sub]}" "$A_PRESENT" "$A_TOTAL"
            print_percent "$A_PRESENT" "$A_TOTAL"
            printf ') | правильные ответы: %s | попытки: %s | средний балл: ' "$T_CORRECT" "$T_COUNT"
            if ((T_COUNT>0)); then print_average "$T_GRADE_SUM" "$T_COUNT"; else printf 'нет данных'; fi
            printf '\n'
        done
    fi
    printf 'Заметки преподавателя:\n'
    show_note "$STUDENT" || printf 'Заметки отсутствуют.\n'
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
show_ranking() {
    local student tmp score
    ask_group || return 1
    select_subject || return 1
    tmp="$BASE/.ranking.$$"; : > "$tmp" || return 1
    while IFS= read -r student || [[ -n "$student" ]]; do
        collect_tests "$GROUP" "$student"
        if ((T_COUNT>0)); then score=$((T_GRADE_SUM*10000/T_COUNT)); printf '%d;%s;%d;%d\n' "$score" "$student" "$T_GRADE_SUM" "$T_COUNT" >> "$tmp"
        else printf '%d;%s;%d;%d\n' -1 "$student" 0 0 >> "$tmp"; fi
    done < "$DATA/students/groups/$GROUP"
    printf 'Рейтинг группы %s (средний балл по всем попыткам):\n' "$GROUP"
    local rank=0 qsum count
    while IFS=';' read -r score student qsum count; do
        rank=$((rank+1)); printf '%2d. %-22s ' "$rank" "$student"
        if ((count>0)); then print_average "$qsum" "$count"; printf ' (%d попыток)\n' "$count"
        else printf 'нет оценок\n'; fi
    done < <(sort -t';' -k1,1nr -k2,2 "$tmp")
    rm -f -- "$tmp"
}
delete_dossier() {
    local mode answer
    choose_student || return 1
    printf '1 — удалить только заметки, 2 — удалить студента из всех файлов: '
    read -r mode || return 1
    [[ "$mode" == 1 || "$mode" == 2 ]] || { fail 'Неверный вариант.'; return 1; }
    printf 'Подтвердить удаление %s (группа %s)? 1 — да, 2 — нет: ' "$STUDENT" "$GROUP"
    read -r answer || return 1
    [[ "$answer" == 1 ]] || { printf 'Отменено.\n'; return 0; }
    remove_notes "$STUDENT" || return 1
    if [[ "$mode" == 2 ]]; then
        remove_from_group "$GROUP" "$STUDENT" || return 1
        remove_from_attendance "$GROUP" "$STUDENT" || return 1
        remove_from_tests "$GROUP" "$STUDENT" || return 1
    fi
    printf 'Удаление выполнено.\n'
}

main() {
    local choice
    check_data || return 1
    while true; do
        printf '\n===== ЛР №4: АНАЛИЗ СТУДЕНТОВ =====\n'
        printf '1. Лучшая посещаемость за период\n2. Максимум правильных ответов\n3. Найти досье\n4. Удалить досье\n5. Рейтинг успеваемости\n0. Выход\nВыбор: '
        read -r choice || break
        case "$choice" in
            1) show_attendance;; 2) show_leader;; 3) show_dossier;; 4) delete_dossier;; 5) show_ranking;; 0) break;; *) printf 'Введите цифру от 0 до 5.\n';;
        esac
    done
}
main "$@"
