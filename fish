
# fish startup file
# $Id$

function l
    ls -Fx $argv
end

function j
    jobs
end

set fish_prompt "echo '> '"
set fish_title "hostname -s; echo '<'; tty | sed -e 's#/.*/\(.*\)#\1#'; echo '>'; echo ' '; id -un; echo ' '; echo $_; echo ' '; echo $PWD"

