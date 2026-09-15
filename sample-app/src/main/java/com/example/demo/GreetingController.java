package com.example.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * A few endpoints with branching logic so Drill4J has meaningful code to
 * report coverage on as requests exercise different paths.
 */
@RestController
public class GreetingController {

    private final CalculatorService calculator = new CalculatorService();

    @GetMapping("/")
    public Map<String, String> index() {
        return Map.of(
                "app", "drill4j-sample-app",
                "message", "Instrumented by the Drill4J Java agent",
                "endpoints", "/api/hello, /api/calc, /actuator/health");
    }

    @GetMapping("/api/hello")
    public Map<String, String> hello(@RequestParam(defaultValue = "world") String name) {
        String greeting = name.isBlank() ? "Hello, stranger!" : "Hello, " + name + "!";
        return Map.of("greeting", greeting);
    }

    @GetMapping("/api/calc")
    public Map<String, Object> calc(@RequestParam String op,
                                    @RequestParam int a,
                                    @RequestParam int b) {
        int result = calculator.apply(op, a, b);
        return Map.of("op", op, "a", a, "b", b, "result", result);
    }
}
