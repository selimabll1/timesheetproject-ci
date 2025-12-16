@'
pipeline {
  agent any

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  stages {
    stage("Compile") {
      steps {
        bat "mvn -B clean compile"
      }
    }
  }
}
'@ | Set-Content -Encoding utf8 Jenkinsfile
