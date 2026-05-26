# Task 03, bug fix with minimal change

Given a `calculator.py` with one bug and a `test_calculator.py` with one failing test plus a few passing ones, the model must produce a fixed `calculator.py`. After replacement, all tests must pass.

The bug: `avg()` uses integer division (`//`) instead of true division (`/`), so `avg([2, 3])` returns 2 instead of 2.5.
