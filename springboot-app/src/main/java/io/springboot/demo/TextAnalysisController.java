package io.springboot.demo;

import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class TextAnalysisController {

    private final TextAnalysisService service;

    public TextAnalysisController(TextAnalysisService service) {
        this.service = service;
    }

    @PostMapping("/analyze")
    public TextAnalysisResult analyze(@RequestBody TextAnalysisRequest request) {
        String text = (request != null && request.text != null) ? request.text : "";
        return service.analyze(text);
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        return Map.of(
                "status", "UP",
                "mode", "JVM",
                "framework", "Spring Boot"
        );
    }

    @GetMapping("/info")
    public Map<String, Object> info() {
        Runtime rt = Runtime.getRuntime();
        return Map.of(
                "mode", "JVM",
                "framework", "Spring Boot",
                "javaVersion", System.getProperty("java.version", "unknown"),
                "availableProcessors", rt.availableProcessors(),
                "maxMemoryMB", rt.maxMemory() / 1024 / 1024,
                "freeMemoryMB", rt.freeMemory() / 1024 / 1024
        );
    }
}
