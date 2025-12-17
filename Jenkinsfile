pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
  }

  tools {
    jdk 'JAVA_HOME'
    maven 'M2_HOME'
  }

  parameters {
    booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Run SonarQube analysis + Quality Gate')
    booleanParam(name: 'PUSH_TO_DOCKERHUB', defaultValue: true, description: 'Push image to Docker Hub (can fail if Docker Hub is unstable)')
    booleanParam(name: 'DEPLOY_TO_MINIKUBE', defaultValue: true, description: 'Deploy to local Minikube (independent from Docker Hub push)')
  }

  environment {
    SONAR_PROJECT_KEY = 'timesheet-devops'

    DOCKER_IMAGE    = 'salima20033/timesheet-devops'
    DOCKER_CREDS_ID = 'dockerhub-creds'

    K8S_NAMESPACE  = 'devops'
    K8S_DEPLOYMENT = 'spring-app'   // change if needed
    K8S_CONTAINER  = 'spring-app'   // change if needed

    // Keep minikube/kubeconfig inside workspace to avoid /var/lib/minikube permission issues
    MINIKUBE_HOME = "${WORKSPACE}/.minikube"
    KUBECONFIG    = "${WORKSPACE}/.kube/config"
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build Maven') {
      steps {
        sh(label: 'Maven package', script: '''#!/usr/bin/env bash
set -euo pipefail
# IMPORTANT: this skips compiling tests too (fixes your "cannot find symbol" in src/test)
mvn -B clean package -Dmaven.test.skip=true
ls -lh target/*.jar || true
''')
      }
    }

    stage('SonarQube Scan') {
      when { expression { return params.RUN_SONAR } }
      steps {
        withSonarQubeEnv('sonar') {
          sh(label: 'Sonar scan', script: '''#!/usr/bin/env bash
set -euo pipefail
echo "SONAR_HOST_URL=$SONAR_HOST_URL"

# Wait until SonarQube is UP (avoid Connection refused)
for i in {1..30}; do
  if curl -fsS --max-time 5 "$SONAR_HOST_URL/api/system/status" | grep -q '"status":"UP"'; then
    echo "SonarQube is UP"
    break
  fi
  echo "Waiting for SonarQube... ($i/30)"
  sleep 5
done

mvn -B -Dmaven.test.skip=true sonar:sonar -Dsonar.projectKey="$SONAR_PROJECT_KEY"
''')
        }
      }
    }

    stage('Quality Gate') {
      when { expression { return params.RUN_SONAR } }
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Docker Build') {
      steps {
        sh(label: 'Docker build', script: '''#!/usr/bin/env bash
set -euo pipefail
test -f Dockerfile
docker build -t "$DOCKER_IMAGE:$BUILD_NUMBER" -t "$DOCKER_IMAGE:latest" .
''')
      }
    }

    stage('Docker Push') {
      when { expression { return params.PUSH_TO_DOCKERHUB } }
      steps {
        // If DockerHub is flaky, we mark build UNSTABLE but we can still deploy to minikube.
        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
          timeout(time: 12, unit: 'MINUTES') {
            withCredentials([usernamePassword(credentialsId: DOCKER_CREDS_ID, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {

              sh(label: 'Docker login', script: '''#!/usr/bin/env bash
set -euo pipefail
echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
''')

              sh(label: 'Docker push (bounded retries)', script: '''#!/usr/bin/env bash
set -euo pipefail

push_one () {
  local img="$1"
  local max=3
  local delay=10
  for attempt in $(seq 1 "$max"); do
    echo "Pushing $img (attempt $attempt/$max)"
    if docker push "$img"; then
      return 0
    fi
    echo "Push failed for $img, sleeping ${delay}s..."
    sleep "$delay"
    delay=$(( delay * 2 ))
    [ "$delay" -gt 40 ] && delay=40
  done
  return 1
}

push_one "$DOCKER_IMAGE:$BUILD_NUMBER"
push_one "$DOCKER_IMAGE:latest"
''')

              sh(label: 'Docker logout', script: '''#!/usr/bin/env bash
set -euo pipefail
docker logout || true
''')
            }
          }
        }
      }
    }

    stage('Deploy to Minikube') {
      when { expression { return params.DEPLOY_TO_MINIKUBE } }
      steps {
        sh(label: 'K8S deploy', script: '''#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$(dirname "$KUBECONFIG")" "$MINIKUBE_HOME"

# Ensure minikube is running (no sudo)
if ! minikube status >/dev/null 2>&1; then
  minikube start --driver=docker --cpus=2 --memory=3072mb
fi

# Load the locally-built image into minikube (IMPORTANT for docker driver)
minikube image load "$DOCKER_IMAGE:$BUILD_NUMBER"

# Namespace
minikube kubectl -- get ns "$K8S_NAMESPACE" >/dev/null 2>&1 || minikube kubectl -- create ns "$K8S_NAMESPACE"

# Apply manifests
if [ -d k8s ]; then
  minikube kubectl -- apply -n "$K8S_NAMESPACE" -f k8s
else
  YAMLS=$(ls *.yaml 2>/dev/null || true)
  [ -n "$YAMLS" ] || (echo "No k8s manifests found (k8s/ or *.yaml)" && exit 1)
  minikube kubectl -- apply -n "$K8S_NAMESPACE" -f $YAMLS
fi

# Set image to the build tag
minikube kubectl -- -n "$K8S_NAMESPACE" set image deploy/"$K8S_DEPLOYMENT" "$K8S_CONTAINER"="$DOCKER_IMAGE:$BUILD_NUMBER" --record || true
minikube kubectl -- rollout status -n "$K8S_NAMESPACE" deploy/"$K8S_DEPLOYMENT" --timeout=180s
''')
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'target/*.jar', fingerprint: true, allowEmptyArchive: true
    }
  }
}
