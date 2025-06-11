import java.util.Properties
import java.io.File

pluginManagement {
    val flutterSdkPath: String by lazy {
        val properties = Properties()
        FileInputStream("local.properties").use { properties.load(it) }
        val sdkPath = properties.getProperty("flutter.sdk")
            ?: throw GradleException("flutter.sdk not set in local.properties")
        sdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.2.1" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include ':app'
