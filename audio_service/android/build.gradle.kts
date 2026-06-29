group = "com.ryanheise.audioservice"
version = "1.0-SNAPSHOT"
val args = listOf("-Xlint:deprecation", "-Xlint:unchecked")

buildscript {
    // Uncomment when moving to Kotlin
    // val kotlinVersion = "2.3.20"
    val agpVersion = "9.0.1"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:$agpVersion")
        // Uncomment when moving to Kotlin
        // classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.addAll(args)
}

// Uncomment when moving to Kotlin
// val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
// if (agpMajor < 9) {
//    apply(plugin = "org.jetbrains.kotlin.android")
// }

android {
    namespace = "com.ryanheise.audioservice"
    compileSdk = 35

    defaultConfig {
        minSdk = 19
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Uncomment when moving to Kotlin
    // sourceSets {
    //     getByName("main") {
    //         java.srcDirs("src/main/kotlin")
    //     }
    //     getByName("test") {
    //         java.srcDirs("src/test/kotlin")
    //     }
    // }

    lint {
        disable += listOf("InvalidPackage")
    }
}

dependencies {
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.core:core:1.13.1")
}
