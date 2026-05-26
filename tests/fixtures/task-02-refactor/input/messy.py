def doit(x, y, op):
    r = 0
    if op == 'add':
        for i in range(0, 1):
            r = x + y
    elif op == 'sub':
        r = x - y
        r = r
    elif op == 'mul':
        t = 0
        for i in range(y if y >= 0 else -y):
            t = t + x
        r = t if y >= 0 else -t
    elif op == 'div':
        if y == 0:
            raise Exception('nope')
        r = x / y
    else:
        raise Exception('bad op')
    return r


def process_list(items):
    out = []
    for it in items:
        if it is None:
            continue
        if isinstance(it, int):
            if it > 0:
                out.append(it * 2)
            else:
                out.append(it)
        elif isinstance(it, str):
            out.append(it.upper())
        else:
            pass
    return out
