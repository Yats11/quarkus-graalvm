package io.springboot.demo;

import java.util.Map;

public class TextAnalysisResult {
    public String textPreview;
    public int wordCount;
    public int charCount;
    public int sentenceCount;
    public int uniqueWordCount;
    public double avgWordLength;
    public int estimatedReadingTimeSecs;
    public Map<String, Long> top5Words;
    public long processingTimeMs;
    public String processedAt;
    public String mode;
    public String framework;
}
