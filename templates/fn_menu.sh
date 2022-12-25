#!/usr/bin/env bash

menu() {
  readonly C_RESET='\033[0m'
  readonly C_MAGENTA_BG="\033[45m"
  readonly CLEAR_LINE="\033[K"

  declare FLAG_SEARCH=false

  declare FLAG_PAGINATION=false
  declare PAGE_SIZE=100

  # Set flags
  while true; do
    case "$1" in
      -s|--search)
        FLAG_SEARCH=true
        ;;
      -p|--page|--pagination)
        FLAG_PAGINATION=true
        if [[ "$2" =~ ^[0-9]{0,2}$ ]]; then
          PAGE_SIZE=$2
          shift
        else
          PAGE_SIZE=10
        fi
        ;;
      *) break ;;
    esac
    shift
  done

  echo >&2``

  get_cursor_position() { declare POS; read -sdR -p $'\033[6n' POS; echo $POS | cut -c3-; }
  min() { printf "%s\n" "${@:2}" | sort "$1" | head -n1; }
  max() { printf "%s\n" "${@:2}" | sort "$1" | tail -n1; }
  divide_round_up() { echo $((($1 + $2 - 1) / $2)); }
  divide_round_down() { echo "$(awk "BEGIN {print int($1 / $2)}")"; }
  # TODO: Seems to be and escaping issue where the key must assigned to a value
  # DO: `declare key="$(read_keyboard)"; case "$key" in` ...)
  # DON'T: `case "$(read_keyboard)" in` ...)
  read_keyboard() {
    declare k1
    declare k2
    declare k3
    declare k4
    declare k5

    IFS=''
    read -r -s -n1 k1
    [[ $k1 == $'\033' ]] && read -r -s -n1 k2
    [[ $k2 == [ ]] && read -r -s -n1 k3
    [[ $k3 == [0-9] ]] && read -r -s -n1 k4
    [[ $k4 == [0-9] ]] && read -r -s -n1 k5
    unset IFS

    declare key="${k1:-}${k2:-}${k3:-}${k4:-}${k5:-}"
    case "$key" in
      $'\033[A') echo UP ;;
      $'\033[B') echo DOWN ;;
      $'\033[D') echo LEFT ;;
      $'\033[C') echo RIGHT ;;
      $'\177') echo BACKSPACE ;;
      $'\0') echo ENTER;;
      *) echo "$key" ;;
    esac
  }

  declare OPTIONS=("$@")
  declare LIST_LEN="$(min -n $PAGE_SIZE ${#OPTIONS[@]})"

  declare HEADER_LEN=$([[ $FLAG_SEARCH == true ]] && echo "2" || echo "0")
  declare FOOTER_LEN=$([[ $FLAG_PAGINATION == true ]] && echo "2" || echo "0")
  declare FILL_EMPTY=$({
    declare max
    for opt in "${OPTIONS[@]}"; do
      [[ "${#opt}" -gt "$max" ]] && max="${#opt}"
    done
    printf '%*s' $max
  })
  declare CURSOR_POS=$(get_cursor_position)

  declare selected=0
  declare page=0
  declare search=""
  declare options=()
  for opt in "${OPTIONS[@]}"; do
    options+=("$(echo "$opt" | sed -e 's/  / /g' | tr '[[:upper:]]' '[[:lower:]]')")
  done
  declare options_filtered=()

  get_paged_index() { declare i=$(($page * $PAGE_SIZE + $selected)); [[ "${i}" -lt 0 ]] && echo "0" || echo "$i"; }
  get_selected_option() { echo "${options_filtered[$(get_paged_index)]:-}"; }
  go_to() { printf "\033[$((${CURSOR_POS%;*}+${1:-0}));${2:-0}H" >&2; }
  go_to_search() { go_to 0 "$((9+${#search}))"; }
  print_option() { printf "${CLEAR_LINE}${C_RESET} %s\n" "$1" >&2; }
  print_option_selected() { printf "${C_MAGENTA_BG}  %s%s  ${C_RESET}\n" "$1" "${FILL_EMPTY:${#1}}" >&2; }

  draw() {
    options_filtered=()
    declare lower_search=$(echo $search | tr '[[:upper:]]' '[[:lower:]]')

    for index in "${!OPTIONS[@]}"; do
      if [[ "${options[$index]}" == *${lower_search}* ]]; then
        options_filtered+=("${OPTIONS[$index]}")
      fi
    done

    declare options_len="${#options_filtered[@]}"
    declare visible_count=$(min -n "$options_len" $(($options_len - ($PAGE_SIZE * $page))))

    if [[ $selected -ge $visible_count ]]; then
      selected=$(($visible_count-1))
    fi

    go_to
    if [[ $FLAG_SEARCH == true ]]; then
      printf "${CLEAR_LINE}${C_RESET}%s: %s\n" "Search" "$search" >&2
      printf "${CLEAR_LINE}${C_RESET}\n" >&2
    fi

    for (( i=0; i<"$LIST_LEN"; i++ )) {
      declare page_i=$(($page * $PAGE_SIZE + $i))
      declare option="${options_filtered[$page_i]:-}"
      if [[ $page_i == $(get_paged_index) ]]; then
        print_option_selected "$option"
      else
        print_option "$option"
      fi
    }

    if [[ $FLAG_PAGINATION == true ]]; then
      printf "${CLEAR_LINE}${C_RESET}\n" >&2
      printf "${CLEAR_LINE}${C_RESET}%s %d-%d / %d\n" \
        "Results:" \
        $(( $PAGE_SIZE * $page + 1 )) \
        $(min -n $(($PAGE_SIZE * ($page+1))) "$options_len") \
        "$options_len" >&2
    fi

    [[ $FLAG_SEARCH == true ]] && go_to_search
  }

  draw
  while true; do
    # NOTE: `read_keyboard` out must be assigned. Inline use has escaping issue.
    declare key=$(read_keyboard)
    case "$key" in
      ENTER)
        declare option="$(get_selected_option)"
        if [[ "$opt" != "" ]]; then
          go_to "$(($HEADER_LEN + $(min -n ${#options_filtered[@]} $LIST_LEN) + $FOOTER_LEN))" 0
          echo >&2
          echo "$option"
          return
        fi
        ;;
      UP)
        go_to "$(($HEADER_LEN + $selected))"
        print_option "$(get_selected_option)"

        ((selected--))
        [[ "$selected" -lt 0 ]] && selected=$(max -n $(($(min -n "${#options_filtered[@]}" $LIST_LEN) - 1)) 0)

        go_to "$(($HEADER_LEN + $selected))"
        print_option_selected "$(get_selected_option)"
        [ $FLAG_SEARCH == true ] && go_to_search
        ;;
      DOWN)
        go_to "$(($HEADER_LEN + $selected))"
        print_option "$(get_selected_option)"

        ((selected++))
        [[ "$selected" -ge $(min -n "${#options_filtered[@]}" $LIST_LEN) ]] && selected=0

        go_to "$(($HEADER_LEN + $selected))"
        print_option_selected "$(get_selected_option)"
        [[ $FLAG_SEARCH == true ]] && go_to_search
        ;;
      LEFT)
        if [[ $FLAG_PAGINATION == true ]]; then
          ((page--))
          [[ "$page" -lt 0 ]] && page=$(divide_round_down ${#options_filtered[@]} $PAGE_SIZE)
          draw
        fi
        ;;
      RIGHT)
        if [[ $FLAG_PAGINATION == true ]]; then
          ((page++))
          [[ "$page" -gt "$(divide_round_down ${#options_filtered[@]} $PAGE_SIZE)" ]] && page=0
          draw
        fi
        ;;
      BACKSPACE)
        if [[ $FLAG_SEARCH == true && "${#search}" -gt 0 ]]; then
          search="${search:0:((${#search}-1))}"
          draw
        fi
        ;;
      *)
        if [[ $FLAG_SEARCH == true ]]; then
          page=0
          search="${search}${key}"
          draw
        fi
        ;;
    esac
  done
}

readonly GITMOJI=(
"🐛 BUGFIX"
"✨ FEATURE"
"♿️ ACCESSIBILITY"
"👽️ ALIEN"
"📈 ANALYTICS"
"💫 ANIMATION"
"🏗️  ARCHITECTURE"
"🛂 AUTHORIZATION"
"👷 CI"
"💡 COMMENTS"
"🔧 CONFIG"
"🧐 DATA"
"🗃️  DATABASE"
"🚀 DEPLOY"
"⚰️  DEPRECATE"
"📝 DOCUMENTATION"
"🚩 FLAG"
"🩺 HEALTHCHECK"
"🚑️ HOTFIX"
"🌐 I18N"
"🧱 INFRASTRUCTURE"
"📄 LICENSE"
"🚨 LINT"
"🔊 LOGGING"
"🧵 MULTITHREADING"
"📦️ PACKAGE"
"🩹 PATCH"
"⚡️ PERFORMANCE"
"♻️  REFACTOR"
"🔥 REMOVE"
"🚚 RENAME"
"📱 RESPONSIVE"
"🔨 SCRIPT"
"🔒️ SECURITY"
"🔍️ SEO"
"💸 SPONSORSHIP"
"🎨 STRUCTURE"
"💄 STYLE"
"🔖 TAG"
"🧪 TEST"
"🏷️  TYPES"
"✏️  TYPO"
"🦺 VALIDATION"
"🚧 WIP"
)

declare item=$(menu "$@" "${GITMOJI[@]}")
echo "selected ${item##* }"