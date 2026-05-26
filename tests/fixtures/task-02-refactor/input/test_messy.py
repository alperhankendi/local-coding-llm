import pytest
from messy import doit, process_list


def test_add():
    assert doit(2, 3, 'add') == 5

def test_sub():
    assert doit(10, 4, 'sub') == 6

def test_mul_positive():
    assert doit(3, 4, 'mul') == 12

def test_mul_negative():
    assert doit(3, -4, 'mul') == -12

def test_div():
    assert doit(10, 2, 'div') == 5

def test_div_zero():
    with pytest.raises(Exception):
        doit(1, 0, 'div')

def test_bad_op():
    with pytest.raises(Exception):
        doit(1, 1, 'wat')

def test_process_list():
    assert process_list([1, -2, None, 'hi', 3.14, 0]) == [2, -2, 'HI', 0]
