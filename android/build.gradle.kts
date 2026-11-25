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
// flutter_ringtone_player (âm báo đơn mới) còn compileSdk 33, trong khi
// thư viện androidx nó kéo theo cần ≥ 34 → ép plugin này biên dịch với SDK 36.
subprojects {
    if (project.name == "flutter_ringtone_player") {
        val bump: Project.() -> Unit = {
            (extensions.getByName("android") as com.android.build.gradle.BaseExtension)
                .compileSdkVersion(36)
        }
        if (state.executed) bump() else afterEvaluate { bump() }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
