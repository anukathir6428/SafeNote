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

subprojects {
    val project = this
    val configureAction = {
        val android = project.extensions.findByName("android")
        if (android != null) {
            val getNamespace = android.javaClass.methods.find { it.name == "getNamespace" }
            val setNamespace = android.javaClass.methods.find { it.name == "setNamespace" && it.parameterTypes.size == 1 && it.parameterTypes[0] == String::class.java }
            if (getNamespace != null && setNamespace != null) {
                val currentNamespace = getNamespace.invoke(android)
                if (currentNamespace == null) {
                    val manifestFile = project.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifestXml = manifestFile.readText()
                        val matcher = java.util.regex.Pattern.compile("package=\"([^\"]+)\"").matcher(manifestXml)
                        if (matcher.find()) {
                            setNamespace.invoke(android, matcher.group(1))
                        } else {
                            setNamespace.invoke(android, "com.example.${project.name.replace("-", "_")}")
                        }
                    } else {
                        setNamespace.invoke(android, "com.example.${project.name.replace("-", "_")}")
                    }
                }
            }
        }
    }
    if (project.state.executed) {
        configureAction()
    } else {
        project.afterEvaluate { configureAction() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
