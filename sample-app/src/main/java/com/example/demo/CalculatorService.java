package com.example.demo;

/**
 * Simple calculator with several branches. Each operation is a distinct path
 * that will show up as covered / not-covered in the Drill4J UI depending on
 * which requests you send.
 */
public class CalculatorService {

    public int apply(String op, int a, int b) {
        switch (op) {
            case "add":
                return add(a, b);
            case "sub":
                return sub(a, b);
            case "mul":
                return mul(a, b);
            case "div":
                return div(a, b);
            default:
                throw new IllegalArgumentException("Unknown op: " + op);
        }
    }

    int add(int a, int b) {
        return a + b;
    }

    int sub(int a, int b) {
        return a - b;
    }

    int mul(int a, int b) {
        return a * b;
    }

    int div(int a, int b) {
        if (b == 0) {
            throw new IllegalArgumentException("Division by zero");
        }
        return a / b;
    }
}
