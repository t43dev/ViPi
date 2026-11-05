# mt.sh x0 y0 x1 y1 : finger0 down, finger1 down, finger0 up, finger1 up (screen px)
D=/dev/input/event2
SIZE=$(wm size | tail -1 | sed 's/.*: //'); W=${SIZE%x*}; H=${SIZE#*x}
sx() { echo $(( $1 * 32767 / W )); }
sy() { echo $(( $1 * 32767 / H )); }
X0=$(sx $1); Y0=$(sy $2); X1=$(sx $3); Y1=$(sy $4)
sendevent $D 3 47 0; sendevent $D 3 57 100; sendevent $D 3 53 $X0; sendevent $D 3 54 $Y0; sendevent $D 3 58 50; sendevent $D 3 48 5; sendevent $D 0 0 0
sleep 0.08
sendevent $D 3 47 1; sendevent $D 3 57 101; sendevent $D 3 53 $X1; sendevent $D 3 54 $Y1; sendevent $D 3 58 50; sendevent $D 3 48 5; sendevent $D 0 0 0
sleep 0.05
sendevent $D 3 47 0; sendevent $D 3 57 4294967295; sendevent $D 0 0 0
sleep 0.05
sendevent $D 3 47 1; sendevent $D 3 57 4294967295; sendevent $D 0 0 0
