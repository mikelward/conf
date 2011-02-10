import sys

try:
    import readline
    import rlcompleter
except ImportError:
    print >>sys.stderr, 'readline/rlcompleter module not available'
else:
    readline.parse_and_bind('tab: complete')
