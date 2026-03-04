package io.quarkus.demo;

import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;

import java.util.Map;

@Path("/api")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class TextAnalysisResource {

    @Inject
    TextAnalysisService service;

    @POST
    @Path("/analyze")
    public TextAnalysisResult analyze(TextAnalysisRequest request) {
        String text = (request != null && request.text != null) ? request.text : "";
        return service.analyze(text);
    }

    @GET
    @Path("/health")
    public Map<String, Object> health() {
        boolean isNative = System.getProperty("org.graalvm.nativeimage.imagecode") != null;
        return Map.of(
                "status", "UP",
                "mode", isNative ? "native" : "JVM",
                "framework", "Quarkus"
        );
    }

    @GET
    @Path("/info")
    public Map<String, Object> info() {
        boolean isNative = System.getProperty("org.graalvm.nativeimage.imagecode") != null;
        Runtime rt = Runtime.getRuntime();
        return Map.of(
                "mode", isNative ? "native" : "JVM",
                "framework", "Quarkus",
                "javaVersion", System.getProperty("java.version", "unknown"),
                "availableProcessors", rt.availableProcessors(),
                "maxMemoryMB", rt.maxMemory() / 1024 / 1024,
                "freeMemoryMB", rt.freeMemory() / 1024 / 1024
        );
    }
}
