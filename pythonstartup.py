import sys

try:
    import readline
    import rlcompleter
except ImportError:
    print('readline/rlcompleter module not available', file=sys.stderr)
else:
    readline.parse_and_bind('tab: complete')
