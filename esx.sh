# esx.sh (Enfors shell extensions) by Christer Enfors

esc=''
CSI="${esc}["
reverse="${CSI}7m"
red="${CSI}31m"
green="${CSI}32m"
yellow="${CSI}33m"
blue="${CSI}34m"
magenta="${CSI}35m"
cyan="${CSI}36m"
reset="${CSI}0m"

rc_file=".esxrc"

export ESX_VERSION="2.0"

# #
# # Command functions (meant for interactive use)
# #

ehelp() {
    if [ "$#" -lt 1 ]; then
	echo \
"ESX version $ESX_VERSION help topics
==================================================================
Available commands:
    ehelp    - Print this message.
    ecd      - cd command that makes it easy to switch back and
               forth between two directories.
    ejunk    - Move files to a junk directory
    eeject   - Eject the tape in \$eset_tape_device, if any.
    ematch   - Find matching lines in all files recursively.
    emark    - Mark files / directories for later operation.
    ecopy    - Copy marked files to specified directory.
    eclear   - Clear all file / directory marks.
    eset     - View and adjust settings.

Other help topics:
    keys     - Which keys to use to navigate the command line.

For more information about a specific command, type 'ehelp topic'."

    fi

    case $1 in
	"ehelp")
            echo \
                "For information about a specific command, type 'ehelp command'.
For information about which commands are available, type 'ehelp'"
            ;;

	"ecd")
	    echo \
"To switch to another directory, type 'ecd directory'.
To switch back to the original directory, type 'ecd'."
            if [ -n "$ecd_old_dir" ]; then
		echo "Currently stored directory: $ecd_old_dir"
	    else
		echo "There is no directory stored at the moment."
	    fi
            ;;
	
	"ejunk")
	    echo \
"To move files or directories to $HOME/junk, type 'ejunk file(s)'.
If $HOME/junk doesn't exist, it is created.
If you type 'ejunk' without an argument, the contents of your junk
directory is listed."
	    ;;

	"eeject")
	    echo \
"This command ejects the tape if the previous command was successful."
            ;;
	    
         "ematch")
            echo \
"To list all matching lines in all files in the current directory and its
subdirectories (recursively), type:

  $ ematch match-pattern file-pattern"
            echo
            echo \
"For example to find all references to the word \"tree\" in all .txt files,
type:

  $ ematch tree \"*.txt\"

Note that if you use wildcards, then you need to quote that argument."
            ;;
	
#	"esend")
#	    echo \
#"To send a file to a different host, type:
#
#  $ esend hostname file
#
#To send several files, type:
#
#  $ esend hostname file1 file2 ... fileN
#
#The files will be queued for sending on tape. For information on how to
#send the files to tape, type:
#
#  $ ehelp esync"
#	    ;;
#
	"eset")
	    echo \
"To show all settings, type:

  $ eset

To change a setting, for example setting 'pwd_prompt' to 'partial', type:

  $ eset pwd_prompt partial"
            echo
 	    echo "For more information, about a specific setting, type:"
	    echo
            echo "   $ eset (setting)"
            echo
	    echo \
"Valid settings are:
  autosave    - If enabled, settings are saved automatically when you
                change them.
  pwd_prompt  - Turn the display of the present working directory (PWD)
                in your prompt on or off.
  tape_device - Which tape device to use for commands related to tape."
            ;;
        "keys")
            echo \
"ESX configures ksh to use Emacs key bindings:
    Arrow up      - Go to the previous command in the command history.
    Arrow down    - Go to the next command in the command history.
    Esc-Esc       - Tab-style file name completion.
    Ctrl-a        - Go to the beginning of the line.
    Ctrl-e        - Go to the end of the line.
    Ctrl-k        - Delete everything from cursor to the end of the line.
    Esc-backspace - Delete the word before the cursor."
            ;;
        "")
            ;;
	
	*)
	    echo "There is no help for that."
	    ;;
     esac
}

ecd() {
    if [ -n "$1" ]; then
	ecd_old_dir=$PWD
	cd $1
    else
	if [ -z "$ecd_old_dir" ]; then
	    echo >&2 "ecd: no other directory stored."
	    return 1
	else
	    tmpdir=$PWD
	    echo "Changing to: $ecd_old_dir"
	    cd $ecd_old_dir
	    ecd_old_dir=$tmpdir
	fi
    fi
}

ejunk() {
    MkJunkDir
    
    if [ -z "$*" ]; then
	ls $HOME/junk
	return 0
    fi

    mv $* $HOME/junk
    return $?
}

eeject() {
    if [ $? -ne 0 ]; then
	EsxError "eeject: Previous command failed; tape not ejected."
	return $?
    fi

    mt -f $eset_tape_device offline

    if [ $? -eq 0 ]; then
	echo "Tape ejected."
	return 0
    else
	EsxError "eeject: eject command failed."
	return 1
    fi
}

ematch() {
    if [ $# != 2 ]; then

        echo >&2 "Usage: ematch match-pattern file-pattern"
        return 1
    fi

    matchpattern=$1
    filepattern=$2

    grep $matchpattern 'find . -type f -name "$filepattern"'
}

emark() {
    if [ -z "$*" ]; then
	if [ -z "$emarked_files" ]; then
	    echo "No marked files."
	else
	    echo "Marked files:"
	    for file in $emarked_files; do
		echo "  $file"
	    done
	fi
    else
	#do_clear=1
	pwd=`pwd`
	for file in $@; do
	    if [ -e "$file" ]; then
		#if [ $do_clear -eq 1 ]; then
		#    emarked_files=""
		#fi
                #echo "File is now: '$file'"
                file=$(GetAbsolutePath $file)
		if [ -z "$emarked_files" ]; then
		    emarked_files=$file
		else
		    emarked_files="$emarked_files $file"
		fi
		echo "Marked: $file"
		#do_clear=0
	    else
		echo "File doesn't exist: $file"
	    fi
	done
    fi
}

ecopy() {
    if [ $# -gt 1 ]; then
	echo "Usage: ecopy [destination]"
	return 1
    fi

    if [ -z "$emarked_files" ]; then
	echo "There are no marked files. Type 'emark file' to mark a file."
	return 1
    fi

    if [ -n "$1" ]; then
	target_dir=$1
    else
	target_dir=`pwd`
    fi

    num_files_copied=0

    for file in $emarked_files; do
	num_files_copied=$(( $num_files_copied+1 ))
    done

    cp -rp $emarked_files $target_dir

    cp_return_value=$?

    if [ $cp_return_value -eq 0 ]; then
	if [ $num_files_copied -eq 1 ]; then
	    noun="file"
	else
	    noun="files"
	fi
	
	echo "$num_files_copied $noun copied to $target_dir"

        EAskToClearMarkedFiles
    fi
}

eclear() {
    unset emarked_files
    echo "All marks cleared."
}

esend() {
    MkSyncDir
    echo "(Unimplemented)"
}

eset() {
    if [ -z "$*" ]; then
        ShowSettings
	return 0
    fi

    case $1 in
	"autosave")
	    ESetAutoSave $2
	    ;;

#	"input_mode")
#	    ESetInputMode $2
#	    ;;

	"pwd_prompt")
	    ESetPWDPrompt $2
	    ;;

	"tape_device")
	    ESetTapeDevice $2
	    ;;

        "prompt_color")
            ESetPromptColor $2
            AutoSaveSettings
            ;;

	*)
	    EsxError "eset: Unknown option: '$1'"
	    ;;
    esac

    return 0
}

#
# EMark utility functions
#

EAskToClearMarkedFiles() {
    EConfirm "Clear all file marks"

    if [ $? -eq 0 ]; then eclear; fi
}

EConfirm() {
    question=$1

    while true; do
        answer=$(EAskWithDefault "$question (Y/n):" y)

        if [ $answer == "y" ]; then
            return 0;
        fi

        if [ $answer == "n" ]; then
            return 1;
        fi

        echo "Please answer 'y' or 'n'."
    done
}

EAskWithDefault() {
    question=$1
    default=$2

    echo "$question \\c" >/dev/tty
    
    read answer

    if [ -n "$answer" ]; then
        echo "$answer"
    else
        echo "$default"
    fi
}

#
# ESet functions
#

# ESetInputMode() {
#     if [ -z "$1" ]; then
# 	echo "The setting 'input_mode' is currently set to: $eset_input_mode"
# 	echo "To change it, type:"
# 	echo
# 	echo "  $ eset input_mode (value)"
# 	echo
# 	echo "Valid values are: "
# 	echo "  emacs - Emacs mode. Arrow keys work as expected."
# 	echo "  vi    - Vi mode."
# 	return 0
#     fi

#     case $1 in
# 	"emacs")
# 	    set -o emacs
# 	    echo "Emacs keybindings enabled. Use arrow keys for history."
# 	    ;;
# 	"vi")
# 	    set -o vi
# 	    echo "Vi keybindings enabled."
# 	    ;;
# 	*)
# 	    EsxError "eset: input_mode must be set to emacs or vi."
# 	    echo "Vi keybindings enabled."
# 	    return 1
# 	    ;;
#     esac

#      eset_input_mode=$1
#      AutoSaveSettings

#      return 0
# }

ESetPWDPrompt() {
    if [ -z "$1" ]; then
	echo "The setting 'pwd_prompt' is currently set to: $eset_pwd_prompt"
	echo "To change it, type: "
	echo
	echo "  $ eset pwd_prompt (value)"
	echo
	echo "Valid values are:"
	echo "  full    - Show the preset working directory in the prompt."
	echo "  partial - Show only the last part of the PWD."
	echo "  off     - Do not show the PWD in the prompt."
	return 0
    fi
    
    case $1 in
	full)
	    ;;
	partial)
	    ;;
	off)
	    ;;
	*)
	    EsxError "eset: pwd_prompt must be set to full, parital or off."
	    return 1
	    ;;
    esac

    eset_pwd_prompt=$1
    SetPrompt
    AutoSaveSettings
}

ESetTapeDevice() {
    if [ -z "$1" ]; then
	echo \
"This setting defines which tape device (usually /dev/rmt0) is used for
tape related commands. It is currently set to $eset_tape_device.

To change it, type:

  $ eset tape_device (value)

To reset it to the default (/dev/rmt0), type:

  $ eset tape_device reset"
    elif [ "$1" = "reset" ]; then
	echo "Tape device reset to /dev/rmt0."
	eset_tape_device="/dev/rmt0"
    else
	echo "Tape device set to $1."
	eset_tape_device=$1
    fi

    AutoSaveSettings
}

ESetPromptColor() {
    if [ -z "$1" ]; then
        echo \
"This setting allows you to set the color of your prompt, or turn prompt
color off. It is currently set to $eset_prompt_color.

To change it, type:

  $ eset prompt_color (value)

Valid values are:
  green   - Make the prompt green.
  blue    - Make the prompt blue.
  cyan    - Make the prompt cyan - light blue.
  magenta - Make the prompt magenta - purple.
  yellow  - Make the prompt yellow.
  red     - Make the prompt red.
  off     - Disable color prompt."
    else
        case $1 in
            "green")
                prompt_color=$green
                eset_prompt_color="green"
                ;;

            "blue")
                prompt_color=$blue
                eset_prompt_color="blue"
                ;;

            "cyan")
                prompt_color=$cyan
                eset_prompt_color="cyan"
                ;;

            "magenta")
                prompt_color=$magenta
                eset_prompt_color="magenta"
                ;;

            "yellow")
                prompt_color=$yellow
                eset_prompt_color="yellow"
                ;;

            "red")
                prompt_color=$red
                eset_prompt_color="red"
                ;;

            "off")
                prompt_color="";
                eset_prompt_color="off"
                ;;

            *)
                EsxError "eset: Unkown color '$1'."
                return 1
                ;;
        esac
        SetPrompt
    fi
}

ESetAutoSave() {
    if [ -z "$1" ]; then
	echo "The setting 'autosave' is currently set to: $eset_autosave"
	echo "To change it, type: "
	echo
	echo "  $ eset autosave (value)"
	echo
	echo "Valid values are:"
	echo "  on  - Settings are automatically saved when changed."
	echo "  off - Settings are not automatically saved when changed."
	return 0
    fi

    case $1 in
	"on")
	    ;;
	"off")
	    ;;
	*)
	    EsxError "eset: autosave must be set to on or off."
	    return 1;
	    ;;
    esac

    eset_autosave=$1
    AutoSaveSettings
}
#
# Utility functions
#

PrintStatusIfInteractive() {
    if [[ $- = *i* ]]; then
       	PrintStatus
    fi
}

PrintStatus() {
    time=`date +%H:%M:%S`
    echo "$reverse User: $USER -- Time: $time -- PWD: $PWD $reset"
}

SetPrompt() {
    if [ `whoami` = "root" ]; then
        prompt_char="#"
    else
	prompt_char="$"
    fi

    whoami=$(whoami)
    hostname=$(hostname)

    case $eset_pwd_prompt in
	full)
	    pwd='$PWD'
	    ;;

	partial)
	    pwd='${PWD##*/}'
	    ;;

#	off)
#	    PS1=`whoami`:`hostname`:"$prompt_char "
#	    ;;
    esac

#    ESetPromptColor $eset_prompt_color

    if [ "$eset_pwd_prompt" = "off" ]; then
	PS1="$whoami:$hostname $prompt_char "
    else
	PS1="$prompt_color$whoami:$hostname $pwd$reset$prompt_char "
    fi
}

SetAliases() {
    if [ -f "$HOME/.aliases" ]; then . $HOME/.aliases; fi

    alias ls="ls -F"
}

EnableArrowKeys() {
    if [ "$EDITOR" == "vi" ]; then
        echo \
"ESX warning: EDITOR variable set to 'vi'; arrow keys may not work."
    fi
    alias __A=''
    alias __B=''
    alias __C=''
    alias __D=''
#    alias "	"=''
}

MkJunkDir() {
    if [ -z "$HOME" ]; then
        EsxError "MkJunkDir: HOME variable not set."
	return 1
    fi

    if [ ! -e "$HOME/junk" ]; then
	mkdir $HOME/junk
	chmod 700 $HOME/junk
	echo "$HOME/junk directory created for junk storage."
    fi

    return 0
}

MkSyncDir() {
    if [ -z "$HOME" ]; then
	EsxError "MkSyncDir: HOME variable not set."
	return 1
    fi

    sync_dir=$HOME/.esync

    if [ ! -e "$sync_dir" ]; then
	EsxRunCmd mkdir -m 700 $sync_dir
	EsxRunCmd mkdir -m 700 $sync_dir/in
	EsxRunCmd mkdir -m 700 $sync_dir/out
	echo "$HOME/.esync directory created for queues."
    fi
}

GetAbsolutePath() {
    if [ $# -ne 1 ]; then
        EsxError "GetAbsolutePath: Usage: GetAbsolutePath file_name"
        return 1
    fi

    file=$1
    old_dir=$PWD
    absolute_path=$(basename $file)

    cd $(dirname $file)

    while [ $PWD != "/" ]; do
        new_dir=$PWD
        absolute_path="${new_dir##/*/}/$absolute_path"
        cd ..
    done

    echo "$absolute_path"

    cd $old_dir
}

ShowSettings() {
    echo "Setting       Description           Current value"
    echo "============= ===================== ================"
    echo "autosave      Autosave settings     $eset_autosave"
#    echo "input_mode    Emacs or vi keys      $eset_input_mode"
    echo "pwd_prompt    Show PWD in prompt    $eset_pwd_prompt"
    echo "tape_device   Tape device used      $eset_tape_device"
    echo "prompt_color  Color of the prompt   $eset_prompt_color"
    echo
    echo "For more information on a specific setting, type:"
    echo
    echo "  $ eset (setting)"

    return 0
}

LoadSettings() {
    if [ -z "$HOME" ]; then
	EsxError "LoadSettings(): HOME variable not set."
	return 1
    fi

    if [ ! -r "$HOME/$rc_file" ]; then
        ShowNewUserInfo
        SaveSettings >/dev/null
	return 0
    fi

    while read variable value; do
	case $variable in
	    "autosave")
		eset_autosave=$value
		;;
#	    "input_mode")
#		ESetInputMode $value
#		;;
	    "pwd_prompt")
	        eset_pwd_prompt=$value
		;;

	    "tape_device")
		eset_tape_device=$value
		;;

            "prompt_color")
                ESetPromptColor $value
		;;

	    *)
		EsxError "Unknown variable '$variable' in $HOME/$rc_file."
		return 1
		;;
	esac
    done <$HOME/$rc_file

    SetDefaultSettings
}

SetDefaultSettings() {
    if [ -z "$eset_autosave"     ]; then eset_autosave="on";           fi
    if [ -z "$eset_pwd_prompt"   ]; then eset_pwd_prompt="partial";    fi
    if [ -z "$eset_tape_device"  ]; then eset_tape_device="/dev/rmt0"; fi    
    if [ -z "$eset_prompt_color" ]; then ESetPromptColor blue;         fi
}

SaveSettings() {
    SetDefaultSettings
    umask 033
    echo "autosave $eset_autosave"         >  $HOME/$rc_file
#    echo "input_mode $eset_input_mode"     >> $HOME/$rc_file
    echo "pwd_prompt $eset_pwd_prompt"     >> $HOME/$rc_file
    echo "tape_device $eset_tape_device"   >> $HOME/$rc_file
    echo "prompt_color $eset_prompt_color" >> $HOME/$rc_file
    echo "Settings saved."

    return 0
}

AutoSaveSettings() {
    if [ "$eset_autosave" = "on" ]; then
	SaveSettings
    fi

    return 0
}

ShowNewUserInfo() {
    echo
    echo "=================================================================="
    echo "This seems to be the first time you've used ESX. So, a quick"
    echo "introduction:"
    echo
    echo "ESX enhances and configures the standard Korn shell with some"
    echo "extra features, such as, among other things:"
    echo
    echo "  - You can use arrow keys to step through your command line"
    echo "    history, and to go left and right on the current line."
    echo "  - You can use tab-style filename completion by pressing the"
    echo "    Escape key twice."
    echo "  - You can have the present working directory (PWD) fully or"
    echo "    partially displayed in your prompt."
    echo "  - ESX provides an 'ecd' command which works like the ordinary"
    echo "    cd command, except that if you type only 'ecd', it takes"
    echo "    you back to the previous directory."
    echo "  - You can make the prompt have a different color from other"
    echo "    text."
    echo "================================================================="
}

EsxError() {
    if [ -n "$*" ]; then
	echo >&2 "ESX error: $*"
    else
	echo >&2 "ESX: EsxError(): Error message not supplied."
    fi

    return 1
}

ConditionalEnable() {
    if [ `whoami` != "root" ]; then return 0; fi

    echo "Press Ctrl-C within 3 seconds to disable ESX: (   )${CSI}4D\\c"

    i=0
    while [ $? -eq 0 -a $i -lt 3 ]; do
	sleep 1
	echo ".\\c"
	i=$(($i+1))
    done
}

EsxRunCmd() {
    $*

    if [ $? -ne 0 ]; then
	EsxError "Command failed: '$*', exit value: $?"
	return 1
    fi
}

Main() {
    if [[ $- != *i* ]]; then return 0; fi

    ConditionalEnable
    disable=$?
    
    if [ $disable -ne 0 ]; then
	echo "ESX (Enfors Shell Extensions) disabled."
	return 1
    fi

    #eset_autosave="on"
    #eset_pwd_prompt="partial"

    LoadSettings

    EnableArrowKeys
    SetPrompt
    SetAliases

    return 0
}

set -o emacs
Main

if [ $? -ne 0 ]; then return $?; fi

echo
echo "ESX (Enfors shell extensions) version $ESX_VERSION enabled."\
    "Type 'ehelp' for help."
