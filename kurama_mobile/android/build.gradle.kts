allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins still omit Java compile options while targeting Kotlin/JVM 17.
// Configure their Android library extension so AGP creates matching tasks.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}

// AGP 9-aware plugins skip their own Kotlin plugin because they normally use
// built-in Kotlin. This app temporarily keeps built-in Kotlin disabled for
// older audio plugins, so explicitly compile the two Kotlin-only libraries.
subprojects {
    if (name == "file_picker" || name == "workmanager_android") {
        pluginManager.apply("org.jetbrains.kotlin.android")
    }
    if (name == "workmanager_android") {
        afterEvaluate {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
