def add(a, b):
    return a + b


def sub(a, b):
    return a - b


def avg(values):
    if not values:
        raise ValueError('avg of empty list')
    return sum(values) // len(values)


def is_prime(n):
    if n < 2:
        return False
    for i in range(2, n):
        if n % i == 0:
            return False
    return True
