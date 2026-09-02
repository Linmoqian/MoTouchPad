plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.motouchpad.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.motouchpad.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    lint {
        // The locally cached 8.14.3 distribution is intentionally pinned for
        // reproducible builds; 8.14.5 contains no required project fix.
        disable += "AndroidGradlePluginVersion"
    }

    sourceSets {
        getByName("test") {
            resources.srcDir("$rootDir/../protocol/fixtures")
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
