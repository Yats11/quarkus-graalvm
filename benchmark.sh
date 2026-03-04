#!/usr/bin/env bash
# =============================================================================
#  Quarkus Native vs Quarkus JVM vs Spring Boot JVM — One-Command Benchmark
#  Measures: startup time, memory usage, image size, response latency
# =============================================================================
set -euo pipefail

# ── Terminal colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Container engine: prefer Podman, fall back to Docker ─────────────────────
if command -v podman &>/dev/null; then
    CE="podman"
elif command -v docker &>/dev/null; then
    CE="docker"
else
    echo -e "${RED}Error: Neither podman nor docker found. Please install one.${NC}"
    exit 1
fi

# ── Flags ────────────────────────────────────────────────────────────────────
SKIP_BUILD=false
for arg in "$@"; do
    [[ "$arg" == "--skip-build" ]] && SKIP_BUILD=true
done

# ── Image / container names ──────────────────────────────────────────────────
IMG_SB="demo-springboot-jvm"
IMG_QK_JVM="demo-quarkus-jvm"
IMG_QK_NAT="demo-quarkus-native"

PORT_SB=8083
PORT_QK_JVM=8082
PORT_QK_NAT=8081

# ── Test payload ─────────────────────────────────────────────────────────────
PAYLOAD='{"text":"The quick brown fox jumps over the lazy dog. To be or not to be, that is the question. In the beginning God created the heavens and the earth. All that glitters is not gold. The road not taken makes all the difference. Ask not what your country can do for you. Four score and seven years ago our fathers brought forth a new nation."}'

# ─────────────────────────────────────────────────────────────────────────────
print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   ⚡  Quarkus Native  vs  Quarkus JVM  vs  Spring Boot       ║${NC}"
    echo -e "${BOLD}${CYAN}║                   The Java Runtime Benchmark                 ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${DIM}Container engine : ${BOLD}${CE}${NC}"
    echo -e "  ${DIM}Skip build       : ${BOLD}${SKIP_BUILD}${NC}"
    echo ""
}

step()    { echo -e "\n${CYAN}▶ $*${NC}"; }
ok()      { echo -e "${GREEN}  ✓ $*${NC}"; }
warn()    { echo -e "${YELLOW}  ⚠ $*${NC}"; }
err()     { echo -e "${RED}  ✗ $*${NC}"; }

# ─────────────────────────────────────────────────────────────────────────────
check_prereqs() {
    step "Checking prerequisites..."
    local missing=()
    for cmd in "$CE" curl bc; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -gt 0 ]] && { err "Missing: ${missing[*]}"; exit 1; }
    [[ -f "./gradlew" ]] || { err "./gradlew not found — run from the project root"; exit 1; }
    ok "All prerequisites satisfied (using: $CE)"
}

# ─────────────────────────────────────────────────────────────────────────────
build_images() {
    step "Building Spring Boot JVM..."
    ./gradlew :springboot-app:build -q
    $CE build -f springboot-app/src/main/docker/Dockerfile.jvm \
               -t "$IMG_SB" springboot-app/ -q
    ok "Image built: $IMG_SB"

    step "Building Quarkus JVM..."
    ./gradlew :quarkus-app:build -q
    $CE build -f quarkus-app/src/main/docker/Dockerfile.jvm \
               -t "$IMG_QK_JVM" quarkus-app/ -q
    ok "Image built: $IMG_QK_JVM"

    step "Building Quarkus Native (~4 min — GraalVM runs inside $CE container)..."
    echo -e "  ${YELLOW}Coffee time ☕  GraalVM is compiling your app to a native binary...${NC}"
    ./gradlew :quarkus-app:build \
        -Dquarkus.native.enabled=true \
        -Dquarkus.native.container-build=true \
        -Dquarkus.native.container-runtime="$CE" -q
    $CE build -f quarkus-app/src/main/docker/Dockerfile.native \
               -t "$IMG_QK_NAT" quarkus-app/ -q
    ok "Image built: $IMG_QK_NAT"
}

# ─────────────────────────────────────────────────────────────────────────────
get_image_size_mb() {
    local img="$1"
    local bytes
    bytes=$($CE image inspect "$img" --format='{{.Size}}' 2>/dev/null || echo "0")
    echo $(( bytes / 1024 / 1024 ))
}

# ─────────────────────────────────────────────────────────────────────────────
wait_for_ready() {
    local port="$1" name="$2" max=90
    echo -n -e "  Waiting for ${name}..."
    for i in $(seq 1 $max); do
        if curl -sf "http://localhost:${port}/api/health" &>/dev/null; then
            echo -e " ${GREEN}ready in ${i}s${NC}"
            return 0
        fi
        sleep 1
    done
    echo -e " ${RED}TIMED OUT${NC}"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
get_startup_ms() {
    local container="$1" type="$2"
    local log
    log=$($CE logs "$container" 2>&1)
    if [[ "$type" == "quarkus" ]]; then
        # Quarkus: "started in X.XXXs"
        echo "$log" | grep -oP 'started in \K[0-9.]+' | head -1 \
            | awk '{printf "%.0f\n", $1 * 1000}' 2>/dev/null || echo "N/A"
    else
        # Spring Boot: "Started Application in X.XXX seconds"
        echo "$log" | grep -oP 'Started .+ in \K[0-9.]+' | head -1 \
            | awk '{printf "%.0f\n", $1 * 1000}' 2>/dev/null || echo "N/A"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
get_mem_mb() {
    local container="$1"
    local raw
    raw=$($CE stats --no-stream --format "{{.MemUsage}}" "$container" 2>/dev/null \
          | awk '{print $1}')
    # Parse "70.5MiB", "1.23GiB", "350MB", etc.
    python3 -c "
import re, sys
m = '''${raw}'''
n = re.search(r'([0-9.]+)(GiB|MiB|GB|MB|KiB|kB)', m)
if n:
    val, unit = float(n.group(1)), n.group(2)
    if unit in ('GiB', 'GB'): val *= 1024
    elif unit in ('KiB', 'kB'): val /= 1024
    print(int(val))
else:
    print('N/A')
" 2>/dev/null || echo "N/A"
}

# ─────────────────────────────────────────────────────────────────────────────
run_latency_test() {
    local port="$1"
    # 20 warmup requests (JIT gets a chance to kick in)
    for _ in $(seq 1 20); do
        curl -sf -X POST "http://localhost:${port}/api/analyze" \
             -H "Content-Type: application/json" -d "$PAYLOAD" \
             -o /dev/null 2>/dev/null || true
    done
    # 50 timed requests
    local total=0
    for _ in $(seq 1 50); do
        local t
        t=$(curl -sf -X POST "http://localhost:${port}/api/analyze" \
                 -H "Content-Type: application/json" -d "$PAYLOAD" \
                 -o /dev/null -w "%{time_total}" 2>/dev/null || echo "0")
        total=$(echo "$total + $t" | bc)
    done
    echo "scale=1; $total * 1000 / 50" | bc 2>/dev/null || echo "N/A"
}

# ─────────────────────────────────────────────────────────────────────────────
cleanup() {
    local name="$1"
    $CE stop "$name" &>/dev/null || true
    $CE rm   "$name" &>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
benchmark_one() {
    local img="$1" cname="$2" port="$3" type="$4" label="$5"
    step "Benchmarking: ${label}"
    cleanup "$cname"

    $CE run -d -p "${port}:8080" --name "$cname" "$img" &>/dev/null

    wait_for_ready "$port" "$label" || { cleanup "$cname"; echo "N/A N/A N/A"; return; }

    local startup
    startup=$(get_startup_ms "$cname" "$type")

    echo -e "  ${DIM}Running 50 timed requests (20 warmup)...${NC}"
    local latency
    latency=$(run_latency_test "$port")

    sleep 2  # let memory settle
    local mem
    mem=$(get_mem_mb "$cname")

    cleanup "$cname"
    echo "$startup $latency $mem"
}

# ─────────────────────────────────────────────────────────────────────────────
print_results() {
    local sb_s="$1"  sb_l="$2"  sb_m="$3"  sb_i="$4"
    local qj_s="$5"  qj_l="$6"  qj_m="$7"  qj_i="$8"
    local qn_s="$9"  qn_l="${10}" qn_m="${11}" qn_i="${12}"

    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                         BENCHMARK RESULTS                               ║${NC}"
    echo -e "${BOLD}${CYAN}╠════════════════════╦═════════════════╦═══════════════╦══════════════════╣${NC}"
    printf "${BOLD}${CYAN}║${NC} %-18s ${BOLD}${CYAN}║${NC} %-15s ${BOLD}${CYAN}║${NC} %-13s ${BOLD}${CYAN}║${NC} %-16s ${BOLD}${CYAN}║${NC}\n" \
        "Metric" "Spring Boot JVM" "Quarkus JVM" "Quarkus Native"
    echo -e "${BOLD}${CYAN}╠════════════════════╬═════════════════╬═══════════════╬══════════════════╣${NC}"

    printf "${BOLD}${CYAN}║${NC} %-18s ${BOLD}${CYAN}║${NC} %-15s ${BOLD}${CYAN}║${NC} ${YELLOW}%-13s${NC} ${BOLD}${CYAN}║${NC} ${GREEN}%-14s ★${NC} ${BOLD}${CYAN}║${NC}\n" \
        "Startup Time" "${sb_s} ms" "${qj_s} ms" "${qn_s} ms"
    printf "${BOLD}${CYAN}║${NC} %-18s ${BOLD}${CYAN}║${NC} %-15s ${BOLD}${CYAN}║${NC} ${YELLOW}%-13s${NC} ${BOLD}${CYAN}║${NC} ${GREEN}%-14s ★${NC} ${BOLD}${CYAN}║${NC}\n" \
        "Memory (RSS)" "${sb_m} MB" "${qj_m} MB" "${qn_m} MB"
    printf "${BOLD}${CYAN}║${NC} %-18s ${BOLD}${CYAN}║${NC} %-15s ${BOLD}${CYAN}║${NC} ${YELLOW}%-13s${NC} ${BOLD}${CYAN}║${NC} ${GREEN}%-14s ★${NC} ${BOLD}${CYAN}║${NC}\n" \
        "Image Size" "${sb_i} MB" "${qj_i} MB" "${qn_i} MB"
    printf "${BOLD}${CYAN}║${NC} %-18s ${BOLD}${CYAN}║${NC} %-15s ${BOLD}${CYAN}║${NC} ${YELLOW}%-13s${NC} ${BOLD}${CYAN}║${NC} ${GREEN}%-16s${NC} ${BOLD}${CYAN}║${NC}\n" \
        "Avg Latency" "${sb_l} ms" "${qj_l} ms" "${qn_l} ms"

    echo -e "${BOLD}${CYAN}╚════════════════════╩═════════════════╩═══════════════╩══════════════════╝${NC}"
    echo ""

    # Print insights
    echo -e "${BOLD}Key Insights:${NC}"
    if [[ "$qn_s" =~ ^[0-9]+$ && "$sb_s" =~ ^[0-9]+$ && "$sb_s" -gt 0 ]]; then
        local sx; sx=$(echo "scale=0; $sb_s / $qn_s" | bc 2>/dev/null)
        echo -e "  ${GREEN}🚀 Quarkus Native starts ${sx}x faster than Spring Boot JVM${NC}"
    fi
    if [[ "$qn_m" =~ ^[0-9]+$ && "$sb_m" =~ ^[0-9]+$ && "$sb_m" -gt 0 ]]; then
        local mp; mp=$(echo "scale=0; 100 - ($qn_m * 100 / $sb_m)" | bc 2>/dev/null)
        echo -e "  ${GREEN}💾 Quarkus Native uses ${mp}% less memory than Spring Boot JVM${NC}"
    fi
    if [[ "$qn_i" =~ ^[0-9]+$ && "$sb_i" =~ ^[0-9]+$ && "$sb_i" -gt 0 ]]; then
        local ip; ip=$(echo "scale=0; 100 - ($qn_i * 100 / $sb_i)" | bc 2>/dev/null)
        echo -e "  ${GREEN}📦 Quarkus Native image is ${ip}% smaller than Spring Boot JVM${NC}"
    fi
    echo ""
    echo -e "  ${DIM}Run again faster: ./benchmark.sh --skip-build${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
main() {
    print_banner
    check_prereqs

    if [[ "$SKIP_BUILD" == true ]]; then
        step "Skipping build (--skip-build). Using existing images."
        for img in "$IMG_SB" "$IMG_QK_JVM" "$IMG_QK_NAT"; do
            $CE image inspect "$img" &>/dev/null \
                || { err "Image '$img' not found. Run without --skip-build first."; exit 1; }
        done
    else
        build_images
    fi

    # Image sizes
    step "Measuring image sizes..."
    SB_SIZE=$(get_image_size_mb "$IMG_SB")
    QJ_SIZE=$(get_image_size_mb "$IMG_QK_JVM")
    QN_SIZE=$(get_image_size_mb "$IMG_QK_NAT")
    ok "Spring Boot JVM: ${SB_SIZE} MB | Quarkus JVM: ${QJ_SIZE} MB | Quarkus Native: ${QN_SIZE} MB"

    # Run benchmarks
    read -r SB_STARTUP SB_LAT SB_MEM \
        <<< "$(benchmark_one "$IMG_SB"     "sb-bench"     "$PORT_SB"     "springboot" "Spring Boot JVM")"
    read -r QJ_STARTUP QJ_LAT QJ_MEM \
        <<< "$(benchmark_one "$IMG_QK_JVM" "qj-bench"     "$PORT_QK_JVM" "quarkus"    "Quarkus JVM")"
    read -r QN_STARTUP QN_LAT QN_MEM \
        <<< "$(benchmark_one "$IMG_QK_NAT" "qn-bench"     "$PORT_QK_NAT" "quarkus"    "Quarkus Native")"

    print_results \
        "$SB_STARTUP" "$SB_LAT" "$SB_MEM" "$SB_SIZE" \
        "$QJ_STARTUP" "$QJ_LAT" "$QJ_MEM" "$QJ_SIZE" \
        "$QN_STARTUP" "$QN_LAT" "$QN_MEM" "$QN_SIZE"
}

main "$@"
