
# fish startup file
# $Id$

function l
    ls -Fx $argv
end

function j
    jobs
end

function fish_prompt
    if test $status -eq 0
        printf '> '
    else
        printf '? '
    end
end

function fish_title
    printf '%s %s %s' (hostname -s) (id -un) $_
end

