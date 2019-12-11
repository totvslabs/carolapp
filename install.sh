#!/usr/bin/env bash
#// created with https://toolstud.io/data/bash.php

# uncomment next line to have time prefix for every output line
#prefix_fmt='+%H:%M:%S | '
prefix_fmt=""
runasroot=-1
# runasroot = 0 :: don't check anything
# runasroot = 1 :: script MUST run as root
# runasroot = -1 :: script MAY NOT run as root

# set strict mode -  via http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -eo pipefail
IFS=$'\n\t'
hash(){
  if [[ -n $(which md5sum) ]] ; then
    # regular linux
    md5sum | cut -c1-6
  else
    # macos
    md5 | cut -c1-6
  fi
}

# change program version to your own release logic
readonly PROGNAME=$(basename $0 .sh)
readonly PROGFNAME=$(basename $0)
readonly PROGDIR=$(cd $(dirname $0); pwd)
readonly PROGUUID="L:$(< $0 awk 'END {print NR}')-MD:$(< $0 hash)"
readonly PROGVERS="v1.4"
readonly PROGAUTH="info@totvslabs.com"
readonly USERNAME=$(whoami)
readonly TODAY=$(date "+%Y-%m-%d")
readonly PROGIDEN="«${PROGNAME} ${PROGVERS}»"
[[ -z "${TEMP:-}" ]] && TEMP=/tmp

list_options() {
echo -n "
flag|h|help|show help/usage info
flag|v|verbose|show more output (also 'log' statements)
flag|q|quiet|show less output (not even 'out' statements)
flag|f|force|do not ask for confirmation
option|t|tmpdir|where temporary files are stored|$TEMP/$PROGNAME
option|t|logdir|where log files are stored|$TEMP/$PROGNAME
" | grep -v '^#'
}

#####################################################################
################### DO NOT MODIFY BELOW THIS LINE ###################
PROGDATE="??"
os_uname=$(uname -s)
[[ "$os_uname" = "Linux" ]]  && PROGDATE=$(stat -c %y "$0" 2>/dev/null | cut -c1-16) # generic linux
[[ "$os_uname" = "Darwin" ]] && PROGDATE=$(stat -f "%Sm" "$0" 2>/dev/null) # for MacOS

readonly ARGS="$@"
#set -e                                  # Exit immediately on error
verbose=0
quiet=0
piped=0
force=0

[[ $# -gt 0 ]] && [[ $1 == "-v" ]] && verbose=1
#to enable verbose even for option parsing

[[ -t 1 ]] && piped=0 || piped=1        # detect if out put is piped
[[ $(echo -e '\xe2\x82\xac') == '€' ]] && unicode=1 || unicode=0 # detect if unicode is supported

# Defaults
args=()

if [[ $piped -eq 0 ]] ; then
  readonly col_reset="\033[0m"
  readonly col_red="\033[1;31m"
  readonly col_grn="\033[1;32m"
  readonly col_ylw="\033[1;33m"
else
  # no colors for piped content
  readonly col_reset=""
  readonly col_red=""
  readonly col_grn=""
  readonly col_ylw=""
fi

if [[ $unicode -gt 0 ]] ; then
  readonly char_succ="✔"
  readonly char_fail="✖"
  readonly char_alrt="➨"
  readonly char_wait="…"
else
  # no unicode chars if not supported
  readonly char_succ="OK "
  readonly char_fail="!! "
  readonly char_alrt="?? "
  readonly char_wait="..."
fi

readonly nbcols=$(tput cols)
readonly wprogress=$(expr $nbcols - 5)
readonly nbrows=$(tput lines)

tmpfile=""
logfile=""

out() {
  ((quiet)) && return
  local message="$@"
  local prefix=""
  if [[ -n $prefix_fmt ]]; then
    prefix=$(date "$prefix_fmt")
  fi
  printf '%b\n' "$prefix$message";
}
#TIP: use «out» to show any kind of output, except when option --quiet is specified
#TIP:> out "User is [$USERNAME]"

#--- List Input
OLD_SET=$-
set -e

arrow="$(echo -e '\xe2\x9d\xaf')"
checked="$(echo -e '\xe2\x97\x89')"
unchecked="$(echo -e '\xe2\x97\xaf')"

black="$(tput setaf 0)"
red="$(tput setaf 1)"
green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
blue="$(tput setaf 4)"
magenta="$(tput setaf 5)"
cyan="$(tput setaf 6)"
white="$(tput setaf 7)"
bold="$(tput bold)"
normal="$(tput sgr0)"
dim=$'\e[2m'

print() {
  echo "$1"
  tput el
}

on_default() {
  true;
}

on_keypress() {
  local OLD_IFS
  local IFS
  local key
  OLD_IFS=$IFS
  local on_up=${1:-on_default}
  local on_down=${2:-on_default}
  local on_space=${3:-on_default}
  local on_enter=${4:-on_default}
  local on_left=${5:-on_default}
  local on_right=${6:-on_default}
  local on_ascii=${7:-on_default}
  local on_backspace=${8:-on_default}
  _break_keypress=false
  while IFS="" read -rsn1 key; do
      case "$key" in
      $'\x1b')
          read -rsn1 key
          if [[ "$key" == "[" ]]; then
              read -rsn1 key
              case "$key" in
              'A') eval $on_up;;
              'B') eval $on_down;;
              'D') eval $on_left;;
              'C') eval $on_right;;
              esac
          fi
          ;;
      ' ') eval $on_space ' ';;
      [a-z0-9A-Z\!\#\$\&\+\,\-\.\/\;\=\?\@\[\]\^\_\{\}\~]) eval $on_ascii $key;;
      $'\x7f') eval $on_backspace $key;;
      '') eval $on_enter $key;;
      esac
      if [ $_break_keypress = true ]; then
        break
      fi
  done
  IFS=$OLD_IFS
}

gen_index() {
  local k=$1
  local l=0
  if [ $k -gt 0 ]; then
    for l in $(seq $k)
    do
       echo "$l-1" | bc
    done
  fi
}

cleanup() {
  # Reset character attributes, make cursor visible, and restore
  # previous screen contents (if possible).
  tput sgr0
  tput cnorm
  stty echo

  # Restore `set e` option to its orignal value
  if [[ $OLD_SET =~ e ]]
  then set -e
  else set +e
  fi
}

control_c() {
  cleanup
  exit $?
}

on_list_input_up() {
  remove_list_instructions
  tput cub "$(tput cols)"

  printf "  ${_list_options[$_list_selected_index]}"
  tput el

  if [ $_list_selected_index = 0 ]; then
    _list_selected_index=$((${#_list_options[@]}-1))
    tput cud $((${#_list_options[@]}-1))
    tput cub "$(tput cols)"
  else
    _list_selected_index=$((_list_selected_index-1))

    tput cuu1
    tput cub "$(tput cols)"
    tput el
  fi

  printf "${cyan}${arrow} %s ${normal}" "${_list_options[$_list_selected_index]}"
}

on_list_input_down() {
  remove_list_instructions
  tput cub "$(tput cols)"

  printf "  ${_list_options[$_list_selected_index]}"
  tput el

  if [ $_list_selected_index = $((${#_list_options[@]}-1)) ]; then
    _list_selected_index=0
    tput cuu $((${#_list_options[@]}-1))
    tput cub "$(tput cols)"
  else
    _list_selected_index=$((_list_selected_index+1))
    tput cud1
    tput cub "$(tput cols)"
    tput el
  fi
  printf "${cyan}${arrow} %s ${normal}" "${_list_options[$_list_selected_index]}"
}

on_list_input_enter_space() {
  local OLD_IFS
  OLD_IFS=$IFS
  IFS=$'\n'

  tput cud $((${#_list_options[@]}-${_list_selected_index}))
  tput cub "$(tput cols)"

  for i in $(seq $((${#_list_options[@]}+1))); do
    tput el1
    tput el
    tput cuu1
  done
  tput cub "$(tput cols)"

  tput cuf $((${#prompt}+3))
  printf "${cyan}${_list_options[$_list_selected_index]}${normal}"
  tput el

  tput cud1
  tput cub "$(tput cols)"
  tput el

  _break_keypress=true
  IFS=$OLD_IFS
}

remove_list_instructions() {
  if [ $_first_keystroke = true ]; then
    tput cuu $((${_list_selected_index}+1))
    tput cub "$(tput cols)"
    tput cuf $((${#prompt}+3))
    tput el
    tput cud $((${_list_selected_index}+1))
    _first_keystroke=false
  fi
}

_list_input() {
  local i
  local j
  prompt=$1
  eval _list_options=( '"${'${2}'[@]}"' )

  _list_selected_index=0
  _first_keystroke=true

  trap control_c SIGINT EXIT

  stty -echo
  tput civis

  print "${normal}${green}?${normal} ${bold}${prompt}${normal} ${dim}(Use arrow keys)${normal}"

  for i in $(gen_index ${#_list_options[@]}); do
    tput cub "$(tput cols)"
    if [ $i = 0 ]; then
      print "${cyan}${arrow} ${_list_options[$i]} ${normal}"
    else
      print "  ${_list_options[$i]}"
    fi
    tput el
  done

  for j in $(gen_index ${#_list_options[@]}); do
    tput cuu1
  done

  on_keypress on_list_input_up on_list_input_down on_list_input_enter_space on_list_input_enter_space

}


list_input() {
  _list_input "$1" "$2"
  local var_name=$3
  eval $var_name=\'"${_list_options[$_list_selected_index]}"\'
  unset _list_selected_index
  unset _list_options
  unset _break_keypress
  unset _first_keystroke

  cleanup
}

list_input_index() {
  _list_input "$1" "$2"
  local var_name=$3
  eval $var_name=\'"$_list_selected_index"\'
  unset _list_selected_index
  unset _list_options
  unset _break_keypress
  unset _first_keystroke

  cleanup
}
#--- End List Input

progress() {
  ((quiet)) && return
  local message="$@"
  if ((piped)); then
    printf '%b\n' "$message";
    # \r makes no sense in file or pipe
  else

    printf '... %-${wprogress}b\r' "$message                                             ";
    # next line will overwrite this line
  fi
}
#TIP: use «progress» to show one line of progress that will be overwritten by the next output
#TIP:> progress "Now generating file $nb of $total ..."

trap "die \"$PROGIDEN stopped because [\$BASH_COMMAND] fails !\" ; " INT TERM EXIT
safe_exit() {
  [[ -n "$tmpfile" ]] && [[ -f "$tmpfile" ]] && rm "$tmpfile"
  trap - INT TERM EXIT
  exit
}

is_set()      { local target=$1 ; [[ $target -gt 0 ]] ; }
is_empty()    { local target=$1 ; [[ -z $target ]] ; }
is_not_empty() { local target=$1;  [[ -n $target ]] ; }
#TIP: use «is_empty» and «is_not_empty» to test for variables
#TIP:> if ! confirm "Delete file"; then ; echo "skip deletion" ;   fi

is_file() { local target=$1; [[ -f $target ]] ; }
is_dir()  { local target=$1; [[ -d $target ]] ; }

die()     { out "${col_red}${char_fail} $PROGIDEN${col_reset}: $@" >&2; safe_exit; }
fail()    { out "${col_red}${char_fail} $PROGIDEN${col_reset}: $@" >&2; safe_exit; }
#TIP: use «die» to show error message and exit program
#TIP:> if [[ ! -f $output ]] ; then ; die "could not create output" ; fi

alert()   { out "${col_red}${char_alrt}${col_reset}: $@" >&2 ; }                       # print error and continue
#TIP: use «alert» to show alert message but continue
#TIP:> if [[ ! -f $output ]] ; then ; alert "could not create output" ; fi

success() { out "${col_grn}${char_succ}${col_reset}  $@"; }
#TIP: use «success» to show success message but continue
#TIP:> if [[ -f $output ]] ; then ; success "output was created!" ; fi

announce()  { out "${col_grn}${char_wait}${col_reset}  $@"; sleep 1 ; }
#TIP: use «announce» to show the start of a task
#TIP:> announce "now generating the reports"

log() { if [[ $verbose -gt 0 ]] ; then
  out "${col_ylw}# $@${col_reset}"
fi ;   } # for some reason this always fails if I use ((verbose)) &&
#TIP: use «log» to information that will only be visible when -v is specified
#TIP:> log "input file: [$inputname] - [$inputsize] MB"

notify()  {
  if [[ $? == 0 ]] ; then
    success "$@"
  else
    alert "$@"
  fi
}

escape()  { echo $@ | sed 's/\//\\\//g' ; }
#TIP: use «escape» to extra escape '/' paths in regex
#TIP:> sed 's/$(escape $path)//g'

lcase()   { echo $@ | awk '{print tolower($0)}' ; }
ucase()   { echo $@ | awk '{print toupper($0)}' ; }
#TIP: use «lcase» and «ucase» to convert to upper/lower case
#TIP:> param=$(lcase $param)

confirm() { (($force)) && return 0; read -p "$1 [y/N] " -n 1; echo " "; [[ $REPLY =~ ^[Yy]$ ]];}
#TIP: use «confirm» for interactive confirmation before doing something
#TIP:> if ! confirm "Delete file"; then ; echo "skip deletion" ;   fi

os_uname=$(uname -s)
os_bits=$(uname -m)
os_version=$(uname -v)

on_mac()	{ [[ "$os_uname" = "Darwin" ]] ;	}
on_linux()	{ [[ "$os_uname" = "Linux" ]] ;	}
on_ubuntu()	{ [[ -n $(echo $os_version | grep Ubuntu) ]] ;	}

on_32bit()	{ [[ "$os_bits"  = "i386" ]] ;	}
on_64bit()	{ [[ "$os_bits"  = "x86_64" ]] ;	}
#TIP: use «on_mac»/«on_linux»/«on_ubuntu»/'on_32bit'/'on_64bit' to only run things on certain platforms
#TIP:> on_mac && log "Running on MacOS"

usage() {
  out "Program: ${col_grn}$PROGFNAME${col_reset} by ${col_ylw}$PROGAUTH${col_reset}"
  out "Version: ${col_grn}$PROGVERS${col_reset} (${col_ylw}$PROGUUID${col_reset})"
  out "Updated: ${col_grn}$PROGDATE${col_reset}"

  echo -n "Usage: $PROGFNAME"
   list_options \
  | awk '
  BEGIN { FS="|"; OFS=" "; oneline="" ; fulltext="Flags, options and parameters:"}
  $1 ~ /flag/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-10s: [flag] %s [default: off]",$2,$3,$4) ;
    oneline  = oneline " [-" $2 "]"
    }
  $1 ~ /option/  {
    fulltext = fulltext sprintf("\n    -%1s|--%s <%s>: [optn] %s",$2,$3,"val",$4) ;
    if($5!=""){fulltext = fulltext "  [default: " $5 "]"; }
    oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /secret/  {
    fulltext = fulltext sprintf("\n    -%1s|--%s <%s>: [secr] %s",$2,$3,"val",$4) ;
      oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /param/ {
    if($2 == "1"){
          fulltext = fulltext sprintf("\n    %-10s: [parameter] %s","<"$3">",$4);
          oneline  = oneline " <" $3 ">"
     } else {
          fulltext = fulltext sprintf("\n    %-10s: [parameters] %s (1 or more)","<"$3">",$4);
          oneline  = oneline " <" $3 " …>"
     }
    }
    END {print oneline; print fulltext}
  '
}

tips(){
  cat $0 \
  | grep -v '$0' \
  | awk "
  /TIP: / {\$1=\"\"; gsub(/«/,\"$col_grn\"); gsub(/»/,\"$col_reset\"); print \"*\" \$0}
  /TIP:> / {\$1=\"\"; print \" $col_ylw\" \$0 \"$col_reset\"}
  "
}

init_options() {
    local init_command=$(list_options \
    | awk '
    BEGIN { FS="|"; OFS=" ";}
    $1 ~ /flag/   && $5 == "" {print $3"=0; "}
    $1 ~ /flag/   && $5 != "" {print $3"="$5"; "}
    $1 ~ /option/ && $5 == "" {print $3"=\" \"; "}
    $1 ~ /option/ && $5 != "" {print $3"="$5"; "}
    ')
    if [[ -n "$init_command" ]] ; then
        #log "init_options: $(echo "$init_command" | wc -l) options/flags initialised"
        eval "$init_command"
   fi
}

verify_programs(){
  log "Running: on $os_uname ($os_version)"
  listhash=$(echo $* | hash)
  okfile="$PROGDIR/.$PROGNAME.$listhash.verified"
  if [[ -f "$okfile" ]] ; then
    log "Verify : $(echo $*) -- cached]"
  else
    log "Verify : $(echo $*)]"
    okall=1
    for prog in $* ; do
      if [[ -z $(which "$prog") ]] ; then
        alert "$PROGIDEN needs [$prog] but this program cannot be found on this $os_uname machine"
        okall=0
      fi
    done
    if [[ $okall -eq 1 ]] ; then
      (
        echo $PROGNAME: check required programs OK
        echo $*
        date
      ) > "$okfile"
    fi
  fi
}

folder_prep(){
    if [[ -n "$1" ]] ; then
        local folder="$1"
        local maxdays=365
        if [[ -n "$2" ]] ; then
            maxdays=$2
        fi
        if [ ! -d "$folder" ] ; then
            log "Create folder [$folder]"
            mkdir "$folder"
        else
            log "Cleanup: [$folder] - delete files older than $maxdays day(s)"
            find "$folder" -mtime +$maxdays -type f -exec rm {} \;
        fi
	fi
}
#TIP: use «folder_prep» to create a folder if needed and otherwise clean up old files
#TIP:> folder_prep "$logdir" 7 # delete all files olders than 7 days

expects_single_params(){
  list_options | grep 'param|1|' > /dev/null
}

expects_multi_param(){
  list_options | grep 'param|n|' > /dev/null
}

parse_options() {
    ## first process all the -x --xxxx flags and options
    #set -x
    while true; do
      # flag <flag> is savec as $flag = 0/1
      # option <option> is saved as $option
      if [[ $# -eq 0 ]] ; then
        ## all parameters processed
        break
      fi
      if [[ ! $1 = -?* ]] ; then
        ## all flags/options processed
        break
      fi
      local save_option=$(list_options \
        | awk -v opt="$1" '
        BEGIN { FS="|"; OFS=" ";}
        $1 ~ /flag/   &&  "-"$2 == opt {print $3"=1"}
        $1 ~ /flag/   && "--"$3 == opt {print $3"=1"}
        $1 ~ /option/ &&  "-"$2 == opt {print $3"=$2; shift"}
        $1 ~ /option/ && "--"$3 == opt {print $3"=$2; shift"}
        ')
        if [[ -n "$save_option" ]] ; then
          if echo "$save_option" | grep shift >> /dev/null ; then
            log "Found  : $(echo $save_option | cut -d= -f1)=$2"
          else
            log "Found  : $save_option"
          fi
            eval $save_option
        else
            die "cannot interpret option [$1]"
        fi
        shift
    done

    if [[ $help -gt 0 ]] ; then
      echo "### USAGE"
      usage
      echo ""
      echo "### SCRIPT AUTHORING TIPS"
      tips
      safe_exit
    fi

    ## then run through the given parameters
  if expects_single_params ; then
    #log "Process: single params"
    single_params=$(list_options | grep 'param|1|' | cut -d'|' -f3)
    nb_singles=$(echo $single_params | wc -w)
    log "Expect : $nb_singles single parameter(s): $single_params"
    [[ $# -eq 0 ]]  && die "need the parameter(s) [$(echo $single_params)]"

    for param in $single_params ; do
      [[ $# -eq 0 ]] && die "need parameter [$param]"
      [[ -z "$1" ]]  && die "need parameter [$param]"
      log "Found  : $param=$1"
      eval $param="$1"
      shift
    done
  else
    log "No single params to process"
    single_params=""
    nb_singles=0
  fi

  if expects_multi_param ; then
    #log "Process: multi param"
    nb_multis=$(list_options | grep 'param|n|' | wc -l)
    multi_param=$(list_options | grep 'param|n|' | cut -d'|' -f3)
    log "Expect : $nb_multis multi parameter: $multi_param"
    [[ $nb_multis -gt 1 ]]  && die "cannot have >1 'multi' parameter: [$(echo $multi_param)]"
    [[ $nb_multis -gt 0 ]] && [[ $# -eq 0 ]] && die "need the (multi) parameter [$multi_param]"
    # save the rest of the params in the multi param
    if [[ -n "$*" ]] ; then
      log "Found  : $multi_param=$(echo $*)"
      eval "$multi_param=( $* )"
    fi
  else
    log "No multi param to process"
    nb_multis=0
    multi_param=""
    [[ $# -gt 0 ]] && die "cannot interpret extra parameters"
    log "all parameters have been processed"
  fi
}

[[ $runasroot == 1  ]] && [[ $UID -ne 0 ]] && die "MUST be root to run this script"
[[ $runasroot == -1 ]] && [[ $UID -eq 0 ]] && die "CANNOT be root to run this script"

################### DO NOT MODIFY ABOVE THIS LINE ###################
#####################################################################

## Put your helper scripts here
run_only_show_errors(){
  tmpfile=$(mktemp)
  if ( $* ) 2>> $tmpfile >> $tmpfile ; then
    #all OK
    rm $tmpfile
    return 0
  else
    alert "[$(echo $*)] gave an error"
    cat $tmpfile
    rm $tmpfile
    return -1
  fi
}
#TIP: use «run_only_show_errors» to run a program and only show the output if there was an error
#TIP:> run_only_show_errors mv $tmpd/* $outd/


welcome() {

  echo "  _____     _             ${blue}_          _         ${normal}"
  echo " |_   _|__ | |___   _____${blue}| |    __ _| |__  ___ ${normal}"
  echo "   | |/ _ \| __\ \ / / __${blue}| |   / _\` | '_ \/ __|${normal}"
  echo "   | | (_) | |_ \ V /\__ \\${blue} |__| (_| | |_) \__ \\${normal}"
  echo "   |_|\___/ \__| \_/ |___/${blue}_____\__,_|_.__/|___/${normal}"
  echo ""
  echo "This script will help you create your new Carol App."
  echo "Just select which type of Carol App you want to create and answer the questions the script will ask about your new App."
  echo ""
}

## Put your main script here
main() {
	#// the option $tmpdir will be [$TEMP/$PROGNAME] or whatever the user specified with -t [value] or --tmpdir [value]
	#// the parameters $app_type will have to be specified when starting the script
    log "Program: $PROGFNAME $PROGVERS ($PROGUUID)"
    log "Updated: $PROGDATE"
    log "Run as : $USERNAME@$HOSTNAME"
    if [[ -n "$logdir" ]] ; then
      folder_prep "$logdir" 7
      logfile=$logdir/$PROGNAME.$TODAY.log
      log "Logfile: $logfile"
      echo "$(date '+%H:%M:%S') | [$PROGFNAME] $PROGVERS ($PROGUUID) started" >> $logfile
    fi
    verify_programs awk curl cut date echo find grep head printf sed stat tail uname wc python cookiecutter git
    # add programs you need in your script here, like tar, wget, ...

    welcome

    carol_app_types=( 'Online App' 'Batch App' 'Web App')
    list_input "Which Carol App do you want to create?" carol_app_types selected_carol_app

    template=''
    case "$selected_carol_app" in
      'Online App')
        log 'Creating Online App'
        template='https://github.com/totvslabs/cookiecutter-carol-app-online'
      ;;
      'Batch App')
        log 'Creating Batch App'
        template='https://github.com/totvslabs/cookiecutter-carol-app-batch'
      ;;
      'Web App')
        log 'Creating Web App'
        template='https://github.com/totvslabs/cookiecutter-carol-app-web'
      ;;
    esac
    cookiecutter $template
}

#####################################################################
################### DO NOT MODIFY BELOW THIS LINE ###################

log "-------- PREPARE $PROGIDEN" # this will show up even if your main() has errors
init_options
parse_options $@
log "-------- STARTING (main) $PROGIDEN" # this will show up even if your main() has errors
main
log "-------- FINISH   (main) $PROGIDEN" # a start needs a finish
safe_exit
