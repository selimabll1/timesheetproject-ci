pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(true)
  }

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  environment {
    SONAR_PROJECT_KEY = 'timesheet-devops'
    DOCKER_IMAGE = 'salima20033/timesheet-devops'
    DOCKER_CREDS_ID = 'dockerhub-creds'
    K8S_NAMESPACE = 'devops'
    SONAR_HOST_URL = 'http://192.168.56.10:9000'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Maven') {
      steps {
        sh 'mvn -B clean package -Dmaven.test.skip=true'
      }
    }

    stage('Check SonarQube') {
      steps {
        sh """
          curl -fsS ${SONAR_HOST_URL}/api/system/status | grep -q '"status":"UP"'
        """
      }
    }

    stage('MVN SONARQUBE') {
      steps {
        withSonarQubeEnv('sonar') {
          sh """
            mvn -B -Dmaven.test.skip=true sonar:sonar \
              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
              -Dsonar.host.url=${SONAR_HOST_URL}
          """
        }
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Docker Build & Push') {
      steps {
        script {
          def tagBuild = "${DOCKER_IMAGE}:${env.BUILD_NUMBER}"
          def tagLatest = "${DOCKER_IMAGE}:latest"

          sh "docker build -t ${tagBuild} -t ${tagLatest} ."

          withCredentials([usernamePassword(credentialsId: DOCKER_CREDS_ID, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
            sh 'echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin'
            sh "docker push ${tagBuild}"
            sh "docker push ${tagLatest}"
            sh 'docker logout'
          }
        }
      }
    }

    stage('Deploy Kubernetes') {
      steps {
        sh """
          minikube kubectl -- get ns ${K8S_NAMESPACE} >/dev/null 2>&1 || minikube kubectl -- create ns ${K8S_NAMESPACE}
          if [ -d k8s ]; then
            minikube kubectl -- apply -n ${K8S_NAMESPACE} -f k8s
          else
            YAMLS=\$(ls *.yaml 2>/dev/null || true)
            if [ -n "\$YAMLS" ]; then
              minikube kubectl -- apply -n ${K8S_NAMESPACE} -f \$YAMLS
            else
              exit 1
            fi
          fi
          minikube kubectl -- rollout status -n ${K8S_NAMESPACE} deploy/spring-app --timeout=180s
        """
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
    }
  }
}
