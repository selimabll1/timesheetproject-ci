pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(false)
  }

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  parameters {
    booleanParam(name: 'PUSH_TO_DOCKERHUB', defaultValue: true, description: 'Push image to Docker Hub (may fail if Docker Hub returns 502)')
    booleanParam(name: 'DEPLOY_TO_MINIKUBE', defaultValue: true, description: 'Deploy to local Minikube even if DockerHub push fails')
  }

  environment {
    SONAR_PROJECT_KEY = 'timesheet-devops'

    DOCKER_IMAGE    = 'salima20033/timesheet-devops'
    DOCKER_CREDS_ID = 'dockerhub-creds'

    K8S_NAMESPACE    = 'devops'
    DEPLOYMENT_NAME  = 'spring-app'
    CONTAINER_NAME   = 'spring-app'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Maven') {
      steps {
        sh '''
          set -eu
          mvn -B clean package -DskipTests
          ls -lh target/*.jar
        '''
      }
    }

    stage('SonarQube Scan') {
      steps {
        withSonarQubeEnv('sonar') {
          sh '''
            set -eu
            echo "SONAR_HOST_URL=$SONAR_HOST_URL"

            # Wait until SonarQube is UP (max ~5 minutes)
            i=0
            until curl -fsS "$SONAR_HOST_URL/api/system/status" | grep -q '"status":"UP"'; do
              i=$((i+1))
              if [ "$i" -ge 60 ]; then
                echo "SonarQube not UP after waiting."
                curl -fsS "$SONAR_HOST_URL/api/system/status" || true
                exit 1
              fi
              sleep 5
            done

            mvn -B -DskipTests sonar:sonar -Dsonar.projectKey="$SONAR_PROJECT_KEY"
          '''
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

    stage('Docker Build') {
      steps {
        sh '''
          set -eu
          test -f Dockerfile
          docker version
          docker info >/dev/null
        '''
        script {
          env.TAG_BUILD  = "${DOCKER_IMAGE}:${env.BUILD_NUMBER}"
          env.TAG_LATEST = "${DOCKER_IMAGE}:latest"
        }
        sh '''
          set -eu
          docker build -t "$TAG_BUILD" -t "$TAG_LATEST" .
          docker images | head -n 20
        '''
      }
    }

    stage('Docker Push (retry)') {
      when { expression { return params.PUSH_TO_DOCKERHUB } }
      steps {
        withCredentials([usernamePassword(credentialsId: DOCKER_CREDS_ID, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            set -eu
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
          '''
        }

        script {
          def pushWithBackoff = { String image ->
            int max = 6
            int sleepSec = 15
            for (int i = 1; i <= max; i++) {
              echo "Pushing ${image} (attempt ${i}/${max})"
              int rc = sh(script: "docker push '${image}'", returnStatus: true)
              if (rc == 0) {
                echo "✅ Pushed ${image}"
                return
              }
              echo "⚠️ Push failed for ${image} (rc=${rc}). Sleeping ${sleepSec}s then retry..."
              sleep time: sleepSec, unit: 'SECONDS'
              sleepSec = Math.min(sleepSec * 2, 120)
            }
            error "❌ Docker push failed after ${max} attempts: ${image}"
          }

          pushWithBackoff(env.TAG_BUILD)
          pushWithBackoff(env.TAG_LATEST)
        }

        sh 'docker logout || true'
      }
    }

    stage('Deploy to Minikube') {
      when { expression { return params.DEPLOY_TO_MINIKUBE } }
      steps {
        sh '''
          set -eu

          # Make sure minikube is running (try without sudo, then sudo)
          minikube status >/dev/null 2>&1 || sudo -n minikube status >/dev/null 2>&1 || true
          if ! minikube status | grep -q "apiserver: Running"; then
            minikube start --driver=docker || sudo -n minikube start --driver=docker
          fi

          # Ensure namespace exists
          (minikube kubectl -- get ns "$K8S_NAMESPACE" >/dev/null 2>&1) || (minikube kubectl -- create ns "$K8S_NAMESPACE")

          # IMPORTANT: load image into minikube so deployment works even if DockerHub is down
          minikube image load "$TAG_BUILD" || sudo -n minikube image load "$TAG_BUILD"

          # Apply manifests (k8s folder or yaml in root)
          if [ -d k8s ]; then
            minikube kubectl -- apply -n "$K8S_NAMESPACE" -f k8s
          else
            YAMLS=$(ls *.yaml 2>/dev/null || true)
            [ -n "$YAMLS" ] || (echo "No k8s manifests found (k8s/ or *.yaml)" && exit 1)
            minikube kubectl -- apply -n "$K8S_NAMESPACE" -f $YAMLS
          fi

          # Update deployment image to the build tag (so it uses the loaded image)
          minikube kubectl -- set image -n "$K8S_NAMESPACE" deploy/"$DEPLOYMENT_NAME" "$CONTAINER_NAME"="$TAG_BUILD" || true

          # Wait rollout
          minikube kubectl -- rollout status -n "$K8S_NAMESPACE" deploy/"$DEPLOYMENT_NAME" --timeout=180s
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
    }
  }
}
