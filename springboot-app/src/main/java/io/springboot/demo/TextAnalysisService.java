package io.springboot.demo;

import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
public class TextAnalysisService {

    private static final Pattern WHITESPACE = Pattern.compile("\\s");
    private static final Pattern WHITESPACE_SPLIT = Pattern.compile("\\s+");
    private static final Pattern SENTENCE_DELIM = Pattern.compile("[.!?]+");
    private static final Pattern NON_ALPHANUMERIC = Pattern.compile("[^a-zA-Z0-9]");

    public TextAnalysisResult analyze(String text) {
        long startTime = System.currentTimeMillis();

        TextAnalysisResult result = new TextAnalysisResult();
        result.framework = "Spring Boot";
        result.mode = "JVM";
        result.processedAt = DateTimeFormatter.ISO_LOCAL_DATE_TIME.format(LocalDateTime.now());

        if (text == null || text.isBlank()) {
            result.textPreview = "";
            result.top5Words = Collections.emptyMap();
            result.processingTimeMs = System.currentTimeMillis() - startTime;
            return result;
        }

        result.textPreview = text.length() > 120 ? text.substring(0, 120) + "..." : text;

        String[] words = WHITESPACE_SPLIT.split(text.trim());
        result.wordCount = words.length;
        result.charCount = WHITESPACE.matcher(text).replaceAll("").length();

        long sentenceCount = Arrays.stream(SENTENCE_DELIM.split(text))
                .filter(s -> !s.isBlank())
                .count();
        result.sentenceCount = (int) Math.max(1, sentenceCount);

        Set<String> uniqueWords = Arrays.stream(words)
                .map(w -> NON_ALPHANUMERIC.matcher(w.toLowerCase()).replaceAll(""))
                .filter(w -> !w.isEmpty())
                .collect(Collectors.toSet());
        result.uniqueWordCount = uniqueWords.size();

        result.avgWordLength = Math.round(
                Arrays.stream(words).mapToInt(String::length).average().orElse(0.0) * 100.0
        ) / 100.0;

        result.estimatedReadingTimeSecs = Math.max(1, words.length * 60 / 200);

        Map<String, Long> wordFreq = Arrays.stream(words)
                .map(w -> NON_ALPHANUMERIC.matcher(w.toLowerCase()).replaceAll(""))
                .filter(w -> w.length() > 2)
                .collect(Collectors.groupingBy(w -> w, Collectors.counting()));

        result.top5Words = wordFreq.entrySet().stream()
                .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
                .limit(5)
                .collect(Collectors.toMap(
                        Map.Entry::getKey,
                        Map.Entry::getValue,
                        (e1, e2) -> e1,
                        LinkedHashMap::new
                ));

        result.processingTimeMs = System.currentTimeMillis() - startTime;
        return result;
    }
}
