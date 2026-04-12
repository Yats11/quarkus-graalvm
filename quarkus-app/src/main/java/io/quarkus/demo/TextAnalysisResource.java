package io.quarkus.demo;

import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;

import java.util.Map;

@Path("/api")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class TextAnalysisResource {

    private static final boolean IS_NATIVE =
            System.getProperty("org.graalvm.nativeimage.imagecode") != null;

    private static final int MAX_TEXT_LENGTH = 100_000;

    @Inject
    TextAnalysisService service;

    @POST
    @Path("/analyze")
    public TextAnalysisResult analyze(TextAnalysisRequest request) {
        String text = (request != null && request.text != null) ? request.text : "";
        if (text.length() > MAX_TEXT_LENGTH) {
            throw new BadRequestException("Text exceeds maximum allowed length of " + MAX_TEXT_LENGTH + " characters");
        }
        return service.analyze(text);
    }

    @GET
    @Path("/health")
    public Map<String, Object> health() {
        return Map.of(
                "status", "UP",
                "mode", IS_NATIVE ? "native" : "JVM",
                "framework", "Quarkus"
        );
    }

    @GET
    @Path("/info")
    public Map<String, Object> info() {
        Runtime rt = Runtime.getRuntime();
        return Map.of(
                "mode", IS_NATIVE ? "native" : "JVM",
                "framework", "Quarkus",
                "javaVersion", System.getProperty("java.version", "unknown"),
                "availableProcessors", rt.availableProcessors(),
                "maxMemoryMB", rt.maxMemory() / 1024 / 1024,
                "freeMemoryMB", rt.freeMemory() / 1024 / 1024
        );
    }
}
