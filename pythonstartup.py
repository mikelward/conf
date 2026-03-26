import sys

try:
    import readline
    import rlcompleter
except ImportError:
    print('readline/rlcompleter module not available', file=sys.stderr)
else:
    # macOS Python uses libedit, which needs different syntax
    if 'libedit' in readline.__doc__:
        readline.parse_and_bind('bind ^I rl_complete')
    else:
        readline.parse_and_bind('tab: complete')
