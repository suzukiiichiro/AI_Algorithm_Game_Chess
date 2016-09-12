#/bin/bash

#先読み
strength=4
#プレイヤーの設定
namePlayerA="あなた"
aiPlayerA="AI"
colorPlayerA=4
namePlayerB="AI"
aiPlayerB="AI"
colorPlayerB=1

aikeyword="ai"

sleep=1
colorHover=4
hoverInit=false

timestamp=$( date +%s )
selectedX=-1
selectedY=-1
selectedNewX=-1
selectedNewY=-1
A=-1
B=1
originY=4
originX=7
hoverX=0
hoverY=0
labelX=-2
labelY=9
#
# lookup tables
declare -A cacheLookup
declare -A cacheFlag
declare -A cacheDepth
# associative arrays are faster than numeric ones and way more readable
declare -A redraw
# initialize setting - first row
declare -A field
declare -a initline=( 4  2  3  6  5  3  2  4 )
# readable figure names
declare -a figNames=( "(空)" "ポーン" "ナイト" "ビショップ" "ルーク" "クイーン" "キング" )
# ascii figure names (for ascii output)
declare -a asciiNames=( "k" "q" "r" "b" "n" "p" " " "P" "N" "B" "R" "Q" "K" )
# figure weight (for heuristic)
declare -a figValues=( 0 1 5 5 6 17 42 )
#
type stty >/dev/null 2>&1 && useStty=true || useStty=false
# Choose unused color for hover
while (( colorHover == colorPlayerA || colorHover == colorPlayerB )) ; do
  (( colorHover++ ))
done
# Named ANSI colors get terminal dimension
echo -en '\e[18t'
if read -d "t" -s -t 1 tmp ; then
	termDim=(${tmp//;/ })
	termHeight=${termDim[1]}
	termWidth=${termDim[2]}
else
	termHeight=24
	termWidth=80
fi
# Save screen
#if $cursor ; then
	echo -e "\e7\e[s\e[?47h\e[?25l\e[2J\e[H"
	for (( y=0; y<10; y++ )) ; do
		for (( x=-2; x<8; x++ )) ; do
			redraw[$y,$x]=""
		done
	done
#fi
for (( x=0; x<8; x++ )) ; do
	field[0,$x]=${initline[$x]}
	field[7,$x]=$(( (-1) * ${initline[$x]} ))
done
# set pawns
for (( x=0; x<8; x++ )) ; do
	field[1,$x]=1
	field[6,$x]=-1
done
# set empty fields
for (( y=2; y<6; y++ )) ; do
	for (( x=0; x<8; x++ )) ; do
		field[$y,$x]=0
	done
done
initializedGameLoop=true
#
##################################################################
# minimax (game theory) algorithm for evaluate possible movements
# (the heart of your computer enemy)
# currently based on negamax with alpha/beta pruning and transposition tables liked described in
# http://en.wikipedia.org/wiki/Negamax#NegaMax_with_Alpha_Beta_Pruning_and_Transposition_Tables
# Params:
#	  $1	current search depth
#	  $2	alpha (for pruning)
#	  $3	beta (for pruning)
#	  $4	current moving player
#	  $5	preserves the best move (for ai) if true
#   Returns best value as status code
function negamax() {
	local depth=$1
	local a=$2
	local b=$3
	local player=$4
	local save=$5
	# transposition table
	local aSave=$a
	local hash
	hash="$player ${field[@]}"
	if ! $save && test "${cacheLookup[$hash]+set}" && (( ${cacheDepth[$hash]} >= depth )) ; then
		local value=${cacheLookup[$hash]}
		local flag=${cacheFlag[$hash]}
		if (( flag == 0 )) ; then
			return $value
		elif (( flag == 1 && value > a )) ; then
			a=$value
		elif (( flag == -1 && value < b )) ; then
			b=$value
		fi
		if (( a >= b )) ; then
			return $value
		fi
	fi
	# lost own king?
	if ! hasKing "$player" ; then
		cacheLookup[$hash]=$(( strength - depth + 1 ))
		cacheDepth[$hash]=$depth
		cacheFlag[$hash]=0
		return $(( strength - depth + 1 ))
	# use heuristics in depth
	elif (( depth <= 0 )) ; then
		local values=0
		for (( y=0; y<8; y++ )) ; do
			for (( x=0; x<8; x++ )) ; do
				local fig=${field[$y,$x]}
				if (( ${field[$y,$x]} != 0 )) ; then
					local figPlayer=$(( fig < 0 ? -1 : 1 ))
					# a more simple heuristic would be values=$(( $values + $fig ))
					(( values += ${figValues[$fig * $figPlayer]} * figPlayer ))
					# pawns near to end are better
					if (( fig == 1 )) ; then
						if (( figPlayer > 0 )) ; then
							(( values += ( y - 1 ) / 2 ))
						else
							(( values -= ( 6 + y ) / 2 ))
						fi
					fi
				fi
			done
		done
		values=$(( 127 + ( player * values ) ))
		# ensure valid bash return range
		if (( values > 253 - strength )) ; then
			values=$(( 253 - strength ))
		elif (( values < 2 + strength )) ; then
			values=$(( 2 + strength ))
		fi
		cacheLookup[$hash]=$values
		cacheDepth[$hash]=0
		cacheFlag[$hash]=0
		return $values
	# ベストを選択
	else
		local bestVal=0
		local fromY
		local fromX
		local toY
		local toX
		local i
		local j
		for (( fromY=0; fromY<8; fromY++ )) ; do
			for (( fromX=0; fromX<8; fromX++ )) ; do
				local fig=$(( ${field[$fromY,$fromX]} * ( player ) ))
				# precalc possible fields (faster then checking every 8*8 again)
				local targetY=()
				local targetX=()
				local t=0
				# empty or enemy
				if (( fig <= 0 )) ; then
					continue
				# ポーン
				elif (( fig == 1 )) ; then
					targetY[$t]=$(( player + fromY ))
					targetX[$t]=$(( fromX ))
					(( t += 1 ))
					targetY[$t]=$(( 2 * player + fromY ))
					targetX[$t]=$(( fromX ))
					(( t += 1 ))
					targetY[$t]=$(( player + fromY ))
					targetX[$t]=$(( fromX + 1 ))
					(( t += 1 ))
					targetY[$t]=$(( player + fromY ))
					targetX[$t]=$(( fromX - 1 ))
					(( t += 1 ))
				# ナイト
				elif (( fig == 2 )) ; then
					for (( i=-1 ; i<=1 ; i=i+2 )) ; do
						for (( j=-1 ; j<=1 ; j=j+2 )) ; do
							targetY[$t]=$(( fromY + 1 * i ))
							targetX[$t]=$(( fromX + 2 * j ))
							(( t + 1 ))
							targetY[$t]=$(( fromY + 2 * i ))
							targetX[$t]=$(( fromX + 1 * j ))
							(( t + 1 ))
						done
					done
				# キング
				elif (( fig == 6 )) ; then
					for (( i=-1 ; i<=1 ; i++ )) ; do
						for (( j=-1 ; j<=1 ; j++ )) ; do
							targetY[$t]=$(( fromY + i ))
							targetX[$t]=$(( fromX + j ))
							(( t += 1 ))
						done
					done
				else
					# ビショップかクイーン
					if (( fig != 4 )) ; then
						for (( i=-8 ; i<=8 ; i++ )) ; do
							if (( i != 0 )) ; then
								# can be done nicer but avoiding two loops!
								targetY[$t]=$(( fromY + i ))
								targetX[$t]=$(( fromX + i ))
								(( t += 1 ))
								targetY[$t]=$(( fromY - i ))
								targetX[$t]=$(( fromX - i ))
								(( t += 1 ))
								targetY[$t]=$(( fromY + i ))
								targetX[$t]=$(( fromX - i ))
								(( t += 1 ))
								targetY[$t]=$(( fromY - i ))
								targetX[$t]=$(( fromX + i ))
								(( t += 1 ))
							fi
						done
					fi
					# ルークかクイーン
					if (( fig != 3 )) ; then
						for (( i=-8 ; i<=8 ; i++ )) ; do
							if (( i != 0 )) ; then
								targetY[$t]=$(( fromY + i ))
								targetX[$t]=$(( fromX ))
								(( t += 1 ))
								targetY[$t]=$(( fromY - i ))
								targetX[$t]=$(( fromX ))
								(( t += 1 ))
								targetY[$t]=$(( fromY ))
								targetX[$t]=$(( fromX + i ))
								(( t += 1 ))
								targetY[$t]=$(( fromY ))
								targetX[$t]=$(( fromX - i ))
								(( t += 1 ))
							fi
						done
					fi
				fi
				# 全て有効
				for (( j=0; j < t; j++ )) ; do
					local toY=${targetY[$j]}
					local toX=${targetX[$j]}
					# 動かせない
					if (( toY >= 0 && toY < 8 && toX >= 0 && toX < 8 )) &&  canMove "$fromY" "$fromX" "$toY" "$toX" "$player" ; then
						local oldFrom=${field[$fromY,$fromX]};
						local oldTo=${field[$toY,$toX]};
						field[$fromY,$fromX]=0
						field[$toY,$toX]=$oldFrom
						# ポーンからクイーン
						if (( oldFrom == player && toY == ( player > 0 ? 7 : 0 ) )) ;then
							field["$toY,$toX"]=$(( 5 * player ))
						fi
						# 再帰
						negamax $(( depth - 1 )) $(( 255 - b )) $(( 255 - a )) $(( player * (-1) )) false
						local val=$(( 255 - $? ))
						field[$fromY,$fromX]=$oldFrom
						field[$toY,$toX]=$oldTo
						if (( val > bestVal )) ; then
							bestVal=$val
							if $save ; then
								selectedX=$fromX
								selectedY=$fromY
								selectedNewX=$toX
								selectedNewY=$toY
							fi
						fi
						if (( val > a )) ; then
							a=$val
						fi
						if (( a >= b )) ; then
							break 3
						fi
					fi
				done
			done
		done
		cacheLookup[$hash]=$bestVal
		cacheDepth[$hash]=$depth
		if (( bestVal <= aSave )) ; then
			cacheFlag[$hash]=1
		elif (( bestVal >= b )) ; then
			cacheFlag[$hash]=-1
		else
			cacheFlag[$hash]=0
		fi
		return $bestVal
	fi
}
#-------------------------------------------
# アスキーを入力してdecimal asciiを出力する
# Params: $1	ascii character
function ord() {
	LC_CTYPE=C printf '%d' "'$1"
}
#-------------------------------------------
# 次の一手を読み込む
# Returns 0 成功  1は失敗
function inputCoord(){
	inputY=-1
	inputX=-1
	local ret=0
	local t
	local tx
	local ty
	local oldHoverX=$hoverX
	local oldHoverY=$hoverY
	IFS=''
	$useStty && stty echo
		echo -en "\e[?9h"
	while (( inputY < 0 || inputY >= 8 || inputX < 0  || inputX >= 8 )) ; do
		read -sN1 a
		case "$a" in
			$'\e' )
				if read -t0.1 -sN2 b ; then
					case "$b" in
						'[A' | 'OA' )
							hoverInit=true
							if (( --hoverY < 0 )) ; then
								hoverY=0
							fi
							;;
						'[B' | 'OB' )
							hoverInit=true
							if (( ++hoverY > 7 )) ; then
								hoverY=7
							fi
							;;
						'[C' | 'OC' )
							hoverInit=true
							if (( ++hoverX > 7 )) ; then
								hoverX=7
							fi
							;;
						'[D' | 'OD' )
							hoverInit=true
							if (( --hoverX < 0 )) ; then
								hoverX=0
							fi
							;;
						'[3' )
							ret=1
							break
							;;
						'[5' )
							hoverInit=true
							if (( hoverY == 0 )) ; then
                :
							else
								hoverY=0
							fi
							;;
						'[6' )
							hoverInit=true
							if (( hoverY == 7 )) ; then
                :
							else
								hoverY=7
							fi
							;;
						'OH' )
							hoverInit=true
							if (( hoverX == 0 )) ; then
                :
							else
								hoverX=0
							fi
							;;
						'OF' )
							hoverInit=true
							if (( hoverX == 7 )) ; then
                :
							else
								hoverX=7
							fi
							;;
						'[M' )
							read -sN1 t
							read -sN1 tx
							read -sN1 ty
							ty=$(( $(ord "$ty") - 32 - originY ))
								tx=$(( ( $(ord "$tx") - 32 - originX) / 2 ))
							if (( tx >= 0 && tx < 8 && ty >= 0 && ty < 8 )) ; then
								inputY=$ty
								inputX=$tx
								hoverY=$ty
								hoverX=$tx
							else
								ret=1
								break
							fi
							;;
						* )
              :
					esac
				else
					ret=1
					break
				fi
				;;
			$'\t' | $'\n' | ' ' )
				if $hoverInit ; then
					inputY=$hoverY
					inputX=$hoverX
				fi
				;;
			'~' )
				;;
			$'\x7f' | $'\b' )
				ret=1
				break
				;;
			[A-Ha-h] )
				t=$(ord $a)
				if (( t < 90 )) ; then
					inputY=$(( 72 - $(ord $a) ))
				else
					inputY=$(( 104 - $(ord $a) ))
				fi
				hoverY=$inputY
				;;
			[1-8] )
				inputX=$(( a - 1 ))
				hoverX=$inputX
				;;
			* )
        :
				;;
		esac
		if $hoverInit && (( oldHoverX != hoverX || oldHoverY != hoverY )) ; then
			oldHoverX=$hoverX
			oldHoverY=$hoverY
			draw
		fi
	done
		echo -en "\e[?9l"
	$useStty && stty -echo
	return $ret
}
#-----------------------------------------------
# 駒が動かせる範囲であるかをチェック
# Params:
#	  $1	origin Y position
#	  $2	origin X position
#	  $3	target Y position
#	  $4	target X position
#	  $5	current player
# Returns status code 0は動かせる場合
function canMove() {
	local fromY=$1
	local fromX=$2
	local toY=$3
	local toX=$4
	local player=$5
	local i
	if (( fromY < 0 || fromY >= 8 || fromX < 0 || fromX >= 8 || toY < 0 || toY >= 8 || toX < 0 || toX >= 8 || ( fromY == toY && fromX == toX ) )) ; then
		return 1
	fi
	local from=${field[$fromY,$fromX]}
	local to=${field[$toY,$toX]}
	local fig=$(( from * player ))
	if (( from == 0 || from * player < 0 || to * player > 0 || player * player != 1 )) ; then
		return 1
	# pawn
	elif (( fig == 1 )) ; then
		if (( fromX == toX && to == 0 && ( toY - fromY == player || ( toY - fromY == 2 * player && ${field["$((player + fromY)),$fromX"]} == 0 && fromY == ( player > 0 ? 1 : 6 ) ) ) )) ; then
				return 0
			else
				return $(( ! ( (fromX - toX) * (fromX - toX) == 1 && toY - fromY == player && to * player < 0 ) ))
		fi
  # クイーン、ルーク、ビショップ
	elif (( fig == 5 || fig == 4  || fig == 3 )) ; then
		# ルークとクイーン
		if (( fig != 3 )) ; then
			if (( fromX == toX )) ; then
				for (( i = ( fromY < toY ? fromY : toY ) + 1 ; i < ( fromY > toY ? fromY : toY ) ; i++ )) ; do
					if (( ${field[$i,$fromX]} != 0 )) ; then
						return 1
					fi
				done
				return 0
			elif (( fromY == toY )) ; then
				for (( i = ( fromX < toX ? fromX : toX ) + 1 ; i < ( fromX > toX ? fromX : toX ) ; i++ )) ; do
						if (( ${field[$fromY,$i]} != 0 )) ; then
							return 1
						fi
				done
				return 0
			fi
		fi
		# ビショップとクイーン
		if (( fig != 4 )) ; then
			if (( ( fromY - toY ) * ( fromY - toY ) != ( fromX - toX ) * ( fromX - toX ) )) ; then
				return 1
			fi
			for (( i = 1 ; i < ( $fromY > toY ? fromY - toY : toY - fromY) ; i++ )) ; do
				if (( ${field[$((fromY + i * (toY - fromY > 0 ? 1 : -1 ) )),$(( fromX + i * (toX - fromX > 0 ? 1 : -1 ) ))]} != 0 )) ; then
					return 1
				fi
			done
			return 0
		fi
		# nothing found? wrong move.
		return 1
	# ナイト
	elif (( fig == 2 )) ; then
		return $(( ! ( ( ( fromY - toY == 2 || fromY - toY == -2) && ( fromX - toX == 1 || fromX - toX == -1 ) ) || ( ( fromY - toY == 1 || fromY - toY == -1) && ( fromX - toX == 2 || fromX - toX == -2 ) ) ) ))
	# キング
	elif (( fig == 6 )) ; then
		return $(( !( ( ( fromX - toX ) * ( fromX - toX ) ) <= 1 &&  ( ( fromY - toY ) * ( fromY - toY ) ) <= 1 ) ))
	# 動かせない
	else
		error "そこへは移動できません '$from'!"
		exit 1
	fi
}
#------------------------------------------------
# 駒の動き
# Params: $1	current player
# Globals:
#	  $selectedY
#	  $selectedX
#	  $selectedNewY
#	  $selectedNewX
# Return status code 0 動かせる場合
function move() {
	local player=$1
  # canMove() 駒を動かせるか
	if canMove "$selectedY" "$selectedX" "$selectedNewY" "$selectedNewX" "$player" ; then
		local fig=${field[$selectedY,$selectedX]}
		field[$selectedY,$selectedX]=0
		field[$selectedNewY,$selectedNewX]=$fig
		# pawn to queen
		if (( fig == player && selectedNewY == ( player > 0 ? 7 : 0 ) )) ; then
			field[$selectedNewY,$selectedNewX]=$(( 5 * player ))
		fi
		return 0
	fi
	return 1
}
#------------------------------------------------
# unicodeをエスケープ付きで出力
# Params:
#	  $1	first hex unicode character number
#	  $2	second hex unicode character number
#	  $3	third hex unicode character number
#	  $4	integer offset of third hex
function unicode() {
		printf '\\x%s\\x%s\\x%x' "$1" "$2" "$(( 0x$3 + ( $4 ) ))"
}
#------------------------------------------------
# 動かせる範囲を描画
# Params:
#	  $1	y coordinate
#	  $2	x coordinate
#	  $3	true if cursor should be moved to position
function drawField(){
	local y=$1
	local x=$2
	echo -en "\e[0m"
	# move coursor to absolute position
	if $3 ; then
		local yScr=$(( y + originY ))
		local xScr=$(( x * 2 + originX ))
		echo -en "\e[${yScr};${xScr}H"
	fi
	# draw vertical labels
	if (( x==labelX && y >= 0 && y < 8)) ; then
		if $hoverInit && (( hoverY == y )) ; then
				echo -en "\e[3${colorHover}m"
		elif (( selectedY == y )) ; then
			if (( ${field[$selectedY,$selectedX]} < 0 )) ; then
				echo -en "\e[3${colorPlayerA}m"
			else
				echo -en "\e[3${colorPlayerB}m"
			fi
		fi
		# line number (alpha numeric)
			echo -en "$(unicode e2 92 bd -$y) "
	elif (( x>=0 && y==labelY )) ; then
		if $hoverInit && (( hoverX == x )) ; then
				echo -en "\e[3${colorHover}m"
		elif (( selectedX == x )) ; then
			if (( ${field[$selectedY,$selectedX]} < 0 )) ; then
				echo -en "\e[3${colorPlayerA}m"
			else
				echo -en "\e[3${colorPlayerB}m"
			fi
		else
			echo -en "\e[0m"
		fi
			echo -en "$(unicode e2 9e 80 $x )\e[0m "
	# draw field
	elif (( y >=0 && y < 8 && x >= 0 && x < 8 )) ; then
		local f=${field["$y,$x"]}
		local black=false
		if (( ( x + y ) % 2 == 0 )) ; then
			local black=true
		fi
		# black/white fields
		if $black ; then
				echo -en "\e[47;107m"
		else
			$color && echo -en "\e[40m"
		fi
		# background
		if $hoverInit && (( hoverX == x && hoverY == y )) ; then
			if $black ; then
				echo -en "\e[4${colorHover};10${colorHover}m"
			else
				echo -en "\e[4${colorHover}m"
			fi
		elif (( selectedX != -1 && selectedY != -1 )) ; then
			local selectedPlayer=$(( ${field[$selectedY,$selectedX]} > 0 ? 1 : -1 ))
			if (( selectedX == x && selectedY == y )) ; then
				if $black ; then
					echo -en "\e[47m"
				else
					echo -en "\e[40;100m"
				fi
      # 駒を動かせるか canMove()
			elif canMove "$selectedY" "$selectedX" "$y" "$x" "$selectedPlayer" ; then
				if $black ; then
					if (( selectedPlayer < 0 )) ; then
						echo -en "\e[4${colorPlayerA};10${colorPlayerA}m"
					else
						echo -en "\e[4${colorPlayerB};10${colorPlayerB}m"
					fi
				else
					if (( selectedPlayer < 0 )) ; then
						echo -en "\e[4${colorPlayerA}m"
					else
						echo -en "\e[4${colorPlayerB}m"
					fi
				fi
			fi
		fi
		# empty field?
		if (( f == 0 )) ; then
			echo -en "  "
		else
			# figure colors
				if (( selectedX == x && selectedY == y )) ; then
					if (( f < 0 )) ; then
						echo -en "\e[3${colorPlayerA}m"
					else
						echo -en "\e[3${colorPlayerB}m"
					fi
				else
					if (( f < 0 )) ; then
						echo -en "\e[3${colorPlayerA};9${colorPlayerA}m"
					else
						echo -en "\e[3${colorPlayerB};9${colorPlayerB}m"
					fi
				fi
			if (( f > 0 )) ; then
					echo -en "$( unicode e2 99 a0 -$f ) "
			else
				echo -en "$( unicode e2 99 a0 $f ) "
			fi
		fi
	# otherwise: two empty chars (on unicode boards)
	else
		echo -n "  "
	fi
	# clear format
	echo -en "\e[0m\e[8m"
}
# -----------------------------------------------------
# 入力を待つ
# param なし
# return なし
function anyKey(){
	$useStty && stty echo
	echo -e "\e[2m(次手を選択して下さい)\e[0m"
	read -sN1
	$useStty && stty -echo
}
# -----------------------------------------------------
# 盤面を描画
# param なし
# return なし
function draw() {
	local ty
	local tx
	$useStty && stty -echo
	echo -e "\e[H\e[?25l\e[0m\n\e[K$title\e[0m\n\e[K"
	for (( ty=0; ty<10; ty++ )) ; do
		for (( tx=-2; tx<8; tx++ )) ; do
				local t
				t="$(drawField "$ty" "$tx" true)"
				if [[ "${redraw[$ty,$tx]}" != "$t" ]]; then
					echo -n "$t"
					redraw[$ty,$tx]="$t"
					log="[$ty,$tx]"
				fi
		done
	done
	$useStty && stty echo
	echo -en "\e[0m\e[$(( originY + 10 ));0H\e[2K\n\e[2K$message\e[8m"
}
#------------------------------------------------
# エラーメッセージの出力
# params:	$1	message
# return なし
function error() {
		echo -e "\e[0;1;41m $1 \e[0m\n\e[3m(Script exit)\e[0m" >&2
  # anyKey() 入力を待つ
	anyKey
	exit 1
}
#---------------------------------------------
# 無効な移動などの警告
# params: $1	message
# return なし
function warn() {
	message="\e[41m\e[1m$1\e[0m\n" ;
  # draw() 再描画
	draw ;
}
# -----------------------------------------------------
# 駒の名前を出力
# Params: $1	figure
function nameFigure() {
	if (( $1 < 0 )) ; then
		echo -n "${figNames[$1*(-1)]}"
	else
		echo -n "${figNames[$1]}"
	fi
}
# ----------------------------------------------
# 配置を出力
# Params: $1	row position
#	$2	column position
function coord() {
	echo -en "\x$((48-$1))$(($2+1))"
}
#------------------------------------------------
# プレイヤー名を取得
# Params: $1	player
function namePlayer() {
	if (( $1 < 0 )) ; then
			echo -en "\e[3${colorPlayerA}m"
		if isAI "$1" ; then
			echo -n "$aiPlayerA"
		else
			echo -n "$namePlayerA"
		fi
	else
			echo -en "\e[3${colorPlayerB}m"
		if isAI "$1" ; then
			echo -n "$aiPlayerB"
		else
			echo -n "$namePlayerB"
		fi
	fi
		echo -en "\e[0m"
}
# -----------------------------------------------------
# 人間の手番か？
# Params $1	 player 
# Returns status code 0
function input() {
	local player=$1
	SECONDS=0
	message="\e[1m$(namePlayer "$player")\e[0m: の手番です(例:b3)"
	while true ; do
		selectedY=-1
		selectedX=-1
		title="$(namePlayer "$player")の手番"
    # 描画
		draw >&3
    # inputCoord() 配置
		if inputCoord ; then
			selectedY=$inputY
			selectedX=$inputX
			if (( ${field["$selectedY,$selectedX"]} == 0 )) ; then
				warn "駒がありません" >&3
			elif (( ${field["$selectedY,$selectedX"]} * player  < 0 )) ; then
				warn "その駒は選べません" >&3
			else
				local figName=$(nameFigure ${field[$selectedY,$selectedX]} )
				message="\e[1m$(namePlayer "$player")\e[0m: \e[3m$figName\e[0m を $(coord "$selectedY" "$selectedX") から(例:d3)"
        # 描画
				draw >&3
        # inputCoord() 配置
				if inputCoord ; then
					selectedNewY=$inputY
					selectedNewX=$inputX
					if (( selectedNewY == selectedY && selectedNewX == selectedX )) ; then
						warn "動かせません..." >&3
					elif (( ${field[$selectedNewY,$selectedNewX]} * $player > 0 )) ; then
						warn "自分の駒を取る事は出来ません..." >&3
          # 駒を動かす事が出来るなら
					elif move "$player" ; then
						title="$(namePlayer "$player")\e[3m$figName\e[0m を $(coord "$selectedY" "$selectedX") から $(coord "$selectedNewY" "$selectedNewX") へ\e[2m($SECONDS 秒)\e[0m"
						return 0
					else
						warn "その駒は動かせません" >&3
					fi
				fi
			fi
		fi
	done
}
# -----------------------------------------------------
# 打ち手がAIの場合の挙動
# Params $1	player
# return なし
function ai() {
	local player=$1
	local val
	SECONDS=0
	title="$(namePlayer "$player")の手番"
	message="\e[1m$(namePlayer "$player")\e[0m 思考中..."
	draw >&3
  #-----------------
  #AI処理メイン部分
	negamax "$strength" 0 255 "$player" true
  #-----------------
	val=$?
	local figName
	figName=$(nameFigure ${field[$selectedY,$selectedX]} )
	message="\e[1m$( namePlayer "$player" )\e[0m \e[3m$figName\e[0m を $(coord "$selectedY" "$selectedX")から"
	draw >&3
	sleep "$sleep"
	if move $player ; then
		message="\e[1m$( namePlayer "$player" )\e[0m \e[3m$figName\e[0m を $(coord "$selectedY" "$selectedX") から $(coord "$selectedNewY" "$selectedNewX") へ"
		draw >&3
		sleep "$sleep"
		title="$( namePlayer "$player" ) $figName を $(coord "$selectedY" "$selectedX") から $(coord "$selectedNewY" "$selectedNewX" ) へ ($SECONDS 秒)."
	else
		error "[バグ] AIプレイヤーの禁じ手です！"
	fi
}
# -----------------------------------------------------
# プレイヤーはAIか？
# Params: $1	player
# Return AIプレイヤーならstatus codeは 0 
function isAI() {
  local player=$1 ;
	if (( $player < 0 )) ; then
		if [[ "${namePlayerA,,}" == "${aikeyword,,}" ]] ; then
			return 0
		else
			return 1
		fi
	else
		if [[ "${namePlayerB,,}" == "${aikeyword,,}" ]] ; then
			return 0
		else
			return 1
		fi
	fi
}
# -----------------------------------------------------
# チェックされているかを判別
# Params: $1	player
# Return チェックされていなければ return 1
function hasKing() {
  local player=$1 ;
	local x ;
	local y ;
	for (( y=0;y<8;y++ )) ; do
		for (( x=0;x<8;x++ )) ; do
			if (( ${field[$y,$x]} * $player == 6 )) ; then
				return 0
			fi
		done
	done
	return 1
}
# -----------------------------------------------------
#メイン 
# param なし
# return なし
function main(){
	p=1
	while true ; do
    #打ち手の切り替え
		(( p *= (-1) ))
    #チェック？ hasKing()
		if hasKing "$p" ; then
      #AIの手番 isAI()
			if isAI "$p" ; then
        #AI のAI ai()
				ai "$p"
			else
        #HUMANの手番 input()
				input "$p"
			fi
    #チェックだわ
		else
			title="ゲームオーバー"
			message="\e[1m$(namePlayer $(( p * (-1) )) ) の勝利!\e[1m\n"
      #盤面の描画
			draw >&3
      #入力を待ちます anyKey()
			anyKey
			exit 0
		fi
	done 
} 3>&1
main ;
exit ;
