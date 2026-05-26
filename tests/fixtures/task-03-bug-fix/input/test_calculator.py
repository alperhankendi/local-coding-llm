import pytest
from calculator import add, sub, avg, is_prime


def test_add():
    assert add(2, 3) == 5

def test_sub():
    assert sub(10, 4) == 6

def test_avg_integer_result():
    assert avg([2, 4, 6]) == 4

def test_avg_non_integer_result():
    assert avg([2, 3]) == 2.5

def test_avg_empty():
    with pytest.raises(ValueError):
        avg([])

def test_is_prime_true():
    assert is_prime(7) is True

def test_is_prime_false():
    assert is_prime(9) is False
