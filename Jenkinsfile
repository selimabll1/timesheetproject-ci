pipeline {
  agent any

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  stages {
    stage('Compile') {
      steps {
        sh 'mvn -B clean compile'
      }
    }
  }
}