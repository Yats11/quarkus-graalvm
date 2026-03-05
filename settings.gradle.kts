pluginManagement {
    val quarkusPluginVersion: String by settings
    val springBootPluginVersion: String by settings
    val dependencyManagementVersion: String by settings

    repositories {
        mavenCentral()
        gradlePluginPortal()
    }

    plugins {
        id("io.quarkus") version quarkusPluginVersion
        id("org.springframework.boot") version springBootPluginVersion
        id("io.spring.dependency-management") version dependencyManagementVersion
    }
}

rootProject.name = "quarkus-graalvm"

include("quarkus-app", "springboot-app")
