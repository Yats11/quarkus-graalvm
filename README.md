# ⚡ Quarkus Native vs JVM vs Spring Boot

> One command. Three runtimes. Real numbers.

This repository runs **the same REST API** on three Java runtime configurations and benchmarks them head-to-head. The results make a compelling case for what GraalVM native images mean for cloud-native Java.

---

## The Numbers

| Metric | Spring Boot JVM | Quarkus JVM | Quarkus Native |
|:-------|:----------------|:------------|:---------------|
| **Startup Time** | ~2,800 ms | ~1,150 ms | **~49 ms** ⚡ |
| **Memory Usage** | ~350 MB | ~277 MB | **~70 MB** 💾 |
| **Docker Image** | ~250 MB | ~200 MB | **~70 MB** 📦 |
| **Avg Latency** | ~2.4 ms | ~2.2 ms | ~2.1 ms |

> Quarkus Native starts **57× faster** and uses **80% less memory** than Spring Boot JVM.

---

## Quick Start

**Prerequisites:** Podman or Docker, Java 21+, ~10 minutes for the first build.

```bash
git clone https://github.com/Yats11/quarkus-graalvm.git
cd quarkus-graalvm
./benchmark.sh
```

The script builds all three images and benchmarks them automatically. Grab a coffee during the native compilation (~4 min). Run `./benchmark.sh --skip-build` on subsequent runs.

---

## The Application

A **Text Analysis REST API** implemented identically in both Quarkus and Spring Boot. The same endpoints, the same business logic, the same JSON output — everything identical except the framework.

### Endpoints (same in both apps)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/analyze` | Analyze text — returns word count, top words, reading time, and more |
| `GET`  | `/api/health`  | Health check — shows runtime mode (`JVM` or `native`) and framework |
| `GET`  | `/api/info`    | System info — memory, Java version, available processors |

### Sample Request

```bash
# Quarkus Native (port 8081)
curl -X POST http://localhost:8081/api/analyze \
  -H "Content-Type: application/json" \
  -d '{"text": "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs."}'
```

```json
{
  "textPreview": "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.",
  "wordCount": 16,
  "charCount": 70,
  "sentenceCount": 2,
  "uniqueWordCount": 16,
  "avgWordLength": 4.5,
  "estimatedReadingTimeSecs": 1,
  "top5Words": { "the": 2, "quick": 1, "brown": 1, "fox": 1, "jumps": 1 },
  "processingTimeMs": 1,
  "processedAt": "2026-03-04T10:00:00.000",
  "mode": "native",
  "framework": "Quarkus"
}
```

### Swagger UI

Start the Quarkus app locally and visit: `http://localhost:8080/swagger-ui`

---

## Understanding the Results

### Why Startup Time Matters

Most Java apps start in seconds. That seems fine — until you're at scale.

- **Serverless (Lambda, Cloud Functions):** Every cold start adds latency your users feel directly. 49ms vs 2,800ms is the difference between a responsive API and a complaint in Slack.
- **Kubernetes auto-scaling:** When a traffic spike hits, your cluster needs to provision new pods *now*. A 57× faster startup means your scale-out is 57× more responsive.
- **CI/CD integration tests:** Faster startup = faster test suites = shorter feedback loops.

### Why Memory Matters

Cloud RAM is expensive. Multiply it by thousands of containers and the difference is enormous.

- **80% less memory per instance** means you can fit roughly 5 Quarkus Native containers where you'd run 1 Spring Boot container on the same node.
- Lower memory pressure also means fewer GC pauses and more predictable latency.

### Why Image Size Matters

- **Smaller images pull faster** — critical in multi-region deployments and rolling updates.
- **Smaller attack surface** — no JVM = no JVM CVEs.
- **Storage and transfer costs** — multiply by thousands of CI/CD runs per day.

### The Trade-off

| | JVM Build | Native Build |
|--|-----------|--------------|
| **Build time** | ~15 seconds | ~4 minutes |
| **Peak throughput** | High (JIT-warmed) | Slightly lower |
| **Startup time** | Seconds | Milliseconds |
| **Memory footprint** | High | Minimal |
| **Best for** | Long-running monoliths | Microservices, serverless, k8s |

---

## How to Build Manually

### Spring Boot JVM

```bash
./gradlew :springboot-app:build
podman build -f springboot-app/src/main/docker/Dockerfile.jvm \
             -t demo-springboot-jvm springboot-app/
podman run -i --rm -p 8083:8080 demo-springboot-jvm
```

### Quarkus JVM

```bash
./gradlew :quarkus-app:build
podman build -f quarkus-app/src/main/docker/Dockerfile.jvm \
             -t demo-quarkus-jvm quarkus-app/
podman run -i --rm -p 8082:8080 demo-quarkus-jvm
```

### Quarkus Native (no local GraalVM needed)

```bash
./gradlew :quarkus-app:build \
    -Dquarkus.native.enabled=true \
    -Dquarkus.native.container-build=true \
    -Dquarkus.native.container-runtime=podman

podman build -f quarkus-app/src/main/docker/Dockerfile.native \
             -t demo-quarkus-native quarkus-app/
podman run -i --rm -p 8081:8080 demo-quarkus-native
```

> **No local GraalVM installation required.** The `-Dquarkus.native.container-build=true` flag runs the GraalVM Mandrel compiler inside a container automatically.

---

## How Quarkus + GraalVM Works

Traditional JVM startup:
1. JVM loads → class loading → bytecode interpretation → JIT compilation of hot paths
2. This whole process happens *every time* the app starts (seconds)

Quarkus with GraalVM Native Image:
1. At **build time**, GraalVM performs aggressive Ahead-of-Time (AOT) compilation
2. Dead code elimination, reflection resolution, classpath freezing happen once
3. Result: a self-contained Linux binary that starts like a compiled C program

Quarkus was specifically designed for this. Its "build-time boot" philosophy moves all framework overhead — dependency injection wiring, configuration parsing, ORM schema analysis — to compile time. At startup, there is virtually nothing left to do.

---

## Project Structure

```
quarkus-graalvm/
├── benchmark.sh                     ← Run this first
├── quarkus-app/                     ← Quarkus REST API (JVM or native)
│   ├── build.gradle.kts
│   ├── gradle.properties            ← Quarkus version here
│   └── src/main/
│       ├── java/io/quarkus/demo/
│       │   ├── TextAnalysisResource.java
│       │   ├── TextAnalysisService.java
│       │   ├── TextAnalysisRequest.java
│       │   └── TextAnalysisResult.java
│       ├── resources/application.properties
│       └── docker/
│           ├── Dockerfile.jvm
│           └── Dockerfile.native
└── springboot-app/                  ← Spring Boot REST API (JVM)
    ├── build.gradle.kts
    └── src/main/
        ├── java/io/springboot/demo/
        │   ├── Application.java
        │   ├── TextAnalysisController.java
        │   ├── TextAnalysisService.java
        │   ├── TextAnalysisRequest.java
        │   └── TextAnalysisResult.java
        ├── resources/application.properties
        └── docker/
            └── Dockerfile.jvm
```

---

## Tech Stack

| | Version |
|--|---------|
| Quarkus | 3.17.7 |
| Spring Boot | 3.4.3 |
| Java | 21 (LTS) |
| Build | Gradle (Kotlin DSL) |
| Containers | Podman / Docker |
| GraalVM | Mandrel (via container) |

---

## Key Takeaways

1. **Quarkus Native is not a toy.** It runs production REST APIs with sub-50ms startup and sub-75MB memory — at full feature parity.
2. **Even Quarkus JVM beats Spring Boot.** Without native compilation, Quarkus still starts 2.5× faster due to its build-time optimizations.
3. **The build-time trade-off is real but worth it.** A 4-minute native build is the price for instant cloud-native startup. You pay once; your infrastructure pays forever.
4. **No JVM at runtime.** The native image is a self-contained binary. No JVM to patch, no JVM CVEs, no JVM memory overhead.

---

## Learn More

- [Quarkus: Building a Native Executable](https://quarkus.io/guides/building-native-image)
- [Quarkus: Container First Philosophy](https://quarkus.io/container-first/)
- [GraalVM Native Image Documentation](https://www.graalvm.org/latest/reference-manual/native-image/)
- [Quarkus Performance Benchmarks](https://quarkus.io/blog/runtime-performance/)

---

*Built with Quarkus · Spring Boot · GraalVM Mandrel · Gradle · Podman*
