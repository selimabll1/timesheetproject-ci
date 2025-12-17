pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
  }

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  environment {
    SONAR_PROJECT_KEY      = 'timesheet-devops'
    DOCKER_IMAGE           = 'salima20033/timesheet-devops'
    DOCKER_CREDS_ID        = 'dockerhub-creds'

    DOCKER_CLIENT_TIMEOUT  = '600'
    COMPOSE_HTTP_TIMEOUT   = '600'
    DOCKER_BUILDKIT        = '1'

    K8S_NAMESPACE          = 'workshop'
    K8S_DEPLOYMENT_NAME    = 'spring-app'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Detect Project Files') {
      steps {
        script {
          sh 'pwd && ls -la'

          def pomPath = sh(script: "find . -maxdepth 4 -name pom.xml -print -quit", returnStdout: true).trim()
          if (!pomPath) {
            error("❌ pom.xml not found. Your repo checked out by Jenkins does not contain the Maven project (or it's deeper than 4 levels).")
          }
          env.PROJECT_DIR = sh(script: "dirname '${pomPath}'", returnStdout: true).trim()
          echo "✅ Detected PROJECT_DIR=${env.PROJECT_DIR}"

          def dockerfilePath = sh(script: "find . -maxdepth 4 -name Dockerfile -print -quit", returnStdout: true).trim()
          if (!dockerfilePath) {
            error("❌ Dockerfile not found in repo. Add/commit a file named exactly 'Dockerfile' (no .txt) to Git.")
          }
          env.DOCKERFILE_PATH = dockerfilePath
          echo "✅ Detected DOCKERFILE_PATH=${env.DOCKERFILE_PATH}"
        }
      }
    }

    stage('Build Maven') {
      steps {
        dir("${env.PROJECT_DIR}") {
          sh '''
            set -euo pipefail
            mvn -v
            mvn -B clean package -Dmaven.test.skip=true
            ls -la target || true
            test -f target/timesheet-devops-1.0.jar
          '''
        }
      }
    }

    stage('MVN SONARQUBE') {
      steps {
        dir("${env.PROJECT_DIR}") {
          withSonarQubeEnv('sonar') {
            sh """
              set -euo pipefail
              echo "SONAR_HOST_URL=\$SONAR_HOST_URL"
              curl --retry 30 --retry-connrefused --retry-delay 5 --max-time 10 -fsS "\$SONAR_HOST_URL/api/system/status" | grep -q '"status":"UP"'
              mvn -B -Dmaven.test.skip=true sonar:sonar -Dsonar.projectKey=${SONAR_PROJECT_KEY}
            """
          }
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

    stage('Docker Check') {
      steps {
        sh '''
          set -euo pipefail
          docker version
          docker info > /dev/null
        '''
      }
    }

    stage('Docker Build') {
      steps {
        script {
          env.TAG_BUILD  = "${DOCKER_IMAGE}:${env.BUILD_NUMBER}"
          env.TAG_LATEST = "${DOCKER_IMAGE}:latest"
        }

        sh """
          set -euo pipefail
          echo "Building with Dockerfile: ${env.DOCKERFILE_PATH}"
          echo "Build context (PROJECT_DIR): ${env.PROJECT_DIR}"
          docker build --pull -f "${env.DOCKERFILE_PATH}" -t "${env.TAG_BUILD}" -t "${env.TAG_LATEST}" "${env.PROJECT_DIR}"
        """
      }
    }

    stage('Docker Login') {
      steps {
        withCredentials([usernamePassword(credentialsId: DOCKER_CREDS_ID, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            set -euo pipefail
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
          '''
        }
      }
    }

    stage('Docker Push') {
      steps {
        script {
          def pushWithBackoff = { String img ->
            int maxAttempts = 6
            int sleepSec = 15
            for (int i = 1; i <= maxAttempts; i++) {
              echo "Pushing ${img} (attempt ${i}/${maxAttempts})"
              int rc = sh(script: "docker push '${img}'", returnStatus: true)
              if (rc == 0) { echo "✅ Pushed ${img}"; return }
              echo "⚠️ Push failed for ${img} (rc=${rc}). Sleeping ${sleepSec}s then retry..."
              sleep time: sleepSec, unit: 'SECONDS'
              sleepSec = Math.min(sleepSec * 2, 120)
            }
            error("❌ Docker push failed after ${maxAttempts} attempts: ${img}")
          }

          pushWithBackoff(env.TAG_BUILD)
          pushWithBackoff(env.TAG_LATEST)
        }
      }
    }

    stage('Deploy Kubernetes') {
      steps {
        sh """
          set -euo pipefail
          minikube kubectl -- get ns ${K8S_NAMESPACE} >/dev/null 2>&1 || minikube kubectl -- create ns ${K8S_NAMESPACE}

          if [ -d k8s ]; then
            minikube kubectl -- apply -n ${K8S_NAMESPACE} -f k8s
          else
            YAMLS=\$(ls *.yaml 2>/dev/null || true)
            [ -n "\$YAMLS" ] || (echo "No k8s manifests found" && exit 1)
            minikube kubectl -- apply -n ${K8S_NAMESPACE} -f \$YAMLS
          fi

          minikube kubectl -- rollout status -n ${K8S_NAMESPACE} deploy/${K8S_DEPLOYMENT_NAME} --timeout=180s
        """
      }
    }
  }

  post {
    always {
      sh 'docker logout || true'
      archiveArtifacts artifacts: '**/target/*.jar', fingerprint: true
    }
  }
}
