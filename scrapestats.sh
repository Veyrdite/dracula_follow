#!/bin/bash

temp="/tmp/scrapestats_$$"
mkdir "$temp"
trap "rm -r $temp" QUIT
cd "$temp"

main='http://cgi.cse.unsw.edu.au/~cs1927ass/14s2.dracula'

function grab()
{
	url="$1"
	dest="$2"

	test -f "$dest" && rm "$dest"

	wget -o /dev/null -O "$dest" "$url"

	if [ ! $? -eq 0 ]
	then
		echo Failed to fetch $url!
		exit 1
	fi
}

function isInList()
{
	target="$1"
	shift 1
	others=" $@ " # Note space padding either side

	if ( echo "$others" | grep -q " $target " ) # Note space padding
	then
		return 1
	else
		return 0
	fi
}

function message()
{
	echo -e "\033[1m$*\033[0m"
}


#### Select exact round and group
roundchoice="blah"
groupchoice="blah"

message Fetching index...
grab "${main}/index.php" indexpage

rounds=$( cat indexpage | grep 'index.php?r=' | cut -f3 -d'=' | cut -f1 -d'"')
echo Rounds available: $rounds
while ( isInList "$roundchoice" $rounds )
do
	echo -n 'Choose: '
	read roundchoice
done


message Fetching round ${roundchoice}...
grab "${main}/index.php?r=${roundchoice}" roundpage

echo Groups available:
groupcount=0
while read line
do
	if ( echo "$line" | grep -q '&g=' )
	then
		echo "$line" | cut -f2 -d'&' | cut -f1 -d'<' | sed 's/">/\t/'
		groupcount=$(( $groupcount + 1 ))
	fi
done < roundpage
while ( isInList "$groupchoice" $(seq 0 $groupcount) 'a' )
do
	echo -n "Choose a group number (or a for all): "
	read groupchoice
done


#### Extract results
function extract()
{
	groupNum="$1"

	# Determine the rounds this group played
	asDracula=''
	asHunter=''
	groupName=''

	grab "${main}/index.php?r=${roundchoice}&g=${groupNum}" grouppage

	groupName=$( cat grouppage | grep 'Compilation log' | cut -f3 -d'/' | cut -f1 -d'.' )

	while read line
	do
		line="$( echo $line | grep -v "<p>")" # Avoid erroneous paragraphs

		if ( echo "$line" | grep -q "d-${groupName}" )
		then
			asDracula+=" $( echo "$line" | cut -f2 -d'"' )"
		elif ( echo "$line" | grep -q "h-${groupName}" )
		then
			asHunter+=" $( echo "$line" | cut -f2 -d'"' )"
		fi
	done < grouppage

	# Hack: remove ugly "??"s that appear in some group names
	#asDracula="$( echo $asDracula | sed 's/??//g')"
	#asHunter="$( echo $asHunter | sed 's/??//g')"

	# Determine the 'blood counts' from the end-games of logs
	draculaGames=0
	draculaScore=0
	hunterGames=0
	hunterScore=0
	strangegames=0

	echo -n ' D'
	for log in $asDracula
	do

		grab "${main}/${log}" templog
		score=$(cat templog | grep -A 2 '> End of game:' | egrep 'score: -?[0-9]')

		if [ $? -eq 0 ]
		then
			echo -n '.'
			score=$( echo $score  | cut -f2 -d':' )
			draculaScore=$(( $draculaScore + $score ))
			draculaGames=$(( $draculaGames + 1 ))
		else
			# Something screwed up
			echo -n '?'
			strangegames=$(( $strangegames + 1 ))
		fi
	done

	echo -n ' H'
	for log in $asHunter
	do
		grab "${main}/${log}" templog
		score=$(cat templog | grep -A 2 '> End of game:' | egrep 'score: -?[0-9]')

		if [ $? -eq 0 ]
		then
			echo -n '.'
			score=$( echo $score  | cut -f2 -d':' )
			hunterScore=$(( $hunterScore + $score ))
			hunterGames=$(( $hunterGames + 1 ))
		else
			# Something screwed up
			echo -n '?'
			strangegames=$(( $strangegames + 1 ))
		fi
	done


	### Print results
	dracResults=''
	huntResults=''
	strangestring=''
	if [ $draculaGames -ne 0 ]
	then
		dracResults=$(( $draculaScore / $draculaGames ))
	else
		dracResults="???"
	fi
	if [ $hunterGames -ne 0 ]
	then
		huntResults=$(( $hunterScore / $hunterGames ))
	else
		dracResults="???"
	fi

	test $strangegames -ne 0 && strangestring="with $strangegames unfin games"

	echo -en '\033[99D' # Erase the '.'s we left behind
	printf "%40s %4s %4s    %s\n" "$groupName" $dracResults $huntResults "$strangestring"
}

echo
message Results
echo "After each group name are two numbers.  These are the game scores left behind \
(on average) for their matches.  When playing as Dracula: this should be as high as possible, and visa \
versa for the hunters."
echo Be patient -- this process downloads quite a few MB of data PER MATCH.  Watch as the racing snails \
grow their tails!
message "GROUP NAME                                DRAC HUNT"

if [ $groupchoice == 'a' ]
then
	# Look at everyone's score
	for i in $(seq 0 $groupcount)
	do
		extract $i
	done
else
	# Specific score
	extract $groupchoice
fi
