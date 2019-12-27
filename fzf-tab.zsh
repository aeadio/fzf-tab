zmodload zsh/zutil

# thanks Valodim/zsh-capture-completion
function compadd() {
    # parse all options
    typeset -A apre hpre ipre hsuf asuf isuf dscrs arg_J arg_V \
         arg_X arg_x arg_r arg_R arg_W arg_F arg_M arg_O arg_A arg_D arg_E
    local flag_a flag_k flag_l flag_o flag_1 flag_2 flag_q isfile \
         flag_e flag_Q flag_n flag_U flag_C
    zparseopts -E P:=apre p:=hpre i:=ipre S:=asuf s:=hsuf I:=isuf d:=dscrs \
        J:=arg_J V:=arg_V X:=arg_X x:=arg_x r:=arg_r R:=arg_R W:=arg_W F:=arg_F \
        M:=arg_M O:=arg_O A:=arg_A D:=arg_D E:=arg_E \
        a=flag_a k=flag_k l=flag_l o=flag_o 1=flag_1 2=flag_2 q=flag_q \
        f=isfile e=flag_e Q=flag_Q n=flag_n U=flag_U C=flag_C

    # just delegate and leave if any of -O, -A or -D are given or fzf-tab is not enabled
    if (( $#arg_O || $#arg_A || $#arg_D || ! IN_FZF_TAB )) {
        builtin compadd "$@"
        return $?
    }

    # store matches in $__hits and descriptions in $__dscr
    typeset -a __hits __dscr
    if (( $#dscrs == 1 )) {
        __dscr=( "${(@P)${(v)dscrs}}" )
    }
    builtin compadd -A __hits -D __dscr "$@"
    if (( $#__hits == 0 )) {
        return
    }

    # store these values in compcap
    local -a keys=(ipre apre hpre hsuf asuf isuf PREFIX SUFFIX isfile)
    local expanded __tmp_value="<"$'\0'">" # ensure that compcap's key will always exists
    # NOTE: I don't know why, but if I use `for i ($keys)` here I will get a coredump
    for i ({1..$#keys}) {
        expanded=${(P)keys[i]}
        if [[ -n $expanded ]] {
            __tmp_value+=$'\0'$keys[i]$'\0'$expanded
        }
    }

    # dscr - the string to show to users
    # word - the string to be inserted
    local dscr word
    for i ({1..$#__hits}) {
        word=$__hits[i] && dscr=$__dscr[i]
        if [[ -n $dscr ]] {
            dscr=${dscr//$'\n'}
        } elif [[ -n $word ]] {
            dscr=$word
        } else {
            continue
        }
        compcap[$dscr]=$__tmp_value${word:+$'\0'"word"$'\0'$word}
    }
}

[[ ${FZF_TAB_COMMAND:='fzf'} ]]
[[ ${FZF_TAB_OPTS:='-1 --ansi --cycle --layout=reverse --tiebreak=begin --bind tab:down,ctrl-j:accept --height=50%'} ]]

# select result, first line is query string
function _fzf_tab_select() {
    local query ret
    read -r query
    if [[ $1 == first ]] {
        read -r ret
    } else {
        ret=$($FZF_TAB_COMMAND ${(z)FZF_TAB_OPTS} ${query:+-q $query})
    }
    echo -E ${ret%%$'\0'*}
}

# find longest common prefix of $1 and $2
function _fzf_tab_common_prefix() {
    local str1=$1 str2=$2
    for (( i=1; i<$#1; i++ )) {
        if [[ $str1[i] != $str2[i] ]] {
            break
        }
    }
    echo -E $str1[1,i-1]
}

# print query string(first line) and matches
function _fzf_tab_print_matches() {
    local -a keys=(${(k)compcap})

    # find longest common prefix of command
    local common_prefix=$keys[1]
    for i ($keys) {
        # _fzf_tab_common_prefix is slow, don't call it if they already have common prefix
        (( ${i[(i)$common_prefix]} != 1 )) && common_prefix=$(_fzf_tab_common_prefix $common_prefix $i)
    }
    echo -E $common_prefix

    local dsuf
    for k v (${(kv)compcap}) {
        local -A v=("${(@0)v}")
        # add a character to describe the type of the files
        # TODO: can be color?
        dsuf=
        if [[ -n $v[isfile] ]] {
            # FIXME: a directory with '*|['... in its name can not be detected
            if [[ -L ${~${v[hpre]}}$k ]] {
                dsuf=@
            } elif [[ -d ${~${v[hpre]}}$k ]] {
                dsuf=/
            }
        }
        echo -E $k$'\0'$dsuf
    }
}

# TODO: can I use `compadd` to apply my choice?
function fzf-tab-complete() {
    local -A compcap
    local choice

    IN_FZF_TAB=1
    zle ${fzf_tab_default_completion:-expand-or-complete}
    IN_FZF_TAB=0

    if (( $#compcap == 0 )) {
        return
    } elif (( $#compcap == 1 )) {
        choice=$(_fzf_tab_print_matches | _fzf_tab_select first)
    } else {
        choice=$(_fzf_tab_print_matches | sort | _fzf_tab_select)
    }

    if [[ -n $choice ]] {
        local -A v=("${(@0)${compcap[$choice]}}")
        # if RBUFFER doesn't starts with SUFFIX, the completion position is at LBUFFER
        if (( $RBUFFER[(i)$v[SUFFIX]] != 1 )) {
            LBUFFER=${LBUFFER/%$v[SUFFIX]}
        } else {
            RBUFFER=${RBUFFER/#$v[SUFFIX]}
        }
        # don't add slash if have hsuf, so that /u/l/b can be expanded to /usr/lib/b not /usr/lib//b
        if [[ -z $v[hsuf] && -d ${~${v[hpre]}}$choice ]] {
            v[word]+=/
        }
        LBUFFER=${LBUFFER/%$v[PREFIX]}$v[ipre]$v[apre]$v[hpre]$v[word]$v[hsuf]$v[asuf]$v[isuf]
    }
    zle redisplay
}

zle -N fzf-tab-complete

function disable-fzf-tab() {
    bindkey '^I' expand-or-complete
}

function enable-fzf-tab() {
    local binding=$(bindkey '^I')
    if [[ ! $binding =~ "undefined-key" && $binding != fzf-tab-complete ]] {
        fzf_tab_default_completion=$binding[(w)2]
    }
    bindkey '^I' fzf-tab-complete
}

enable-fzf-tab