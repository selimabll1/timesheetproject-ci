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

  parameters {
    booleanParam(name: 'PUSH_TO_DOCKERHUB', defaultValue: true,  description: 'Push image to Docker Hub (may fail if Docker Hub returns 502)')
    booleanParam(name: 'DEPLOY_TO_MINIKUBE', defaultValue: true,  description: 'Deploy to local Minikube (does NOT start Minikube)')
  }

  environment {
    SONAR_PROJECT_KEY = 'timesheet-devops'
    DOCKER_IMAGE      = 'salima20033/timesheet-devops'
    DOCKER_CREDS_ID   = 'dockerhub-creds'

    K8S_NAMESPACE     = 'devops'
    K8S_DEPLOYMENT    = 'spring-app'          // change if your deployment name is different
    KUBECONFIG        = '/var/lib/jenkins/.kube/config' // must exist (copied from vagrant)
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Detect Project Files') {
      steps {
        sh(label: 'Detect', script: '''
          bash <<'BASH'
          set -euo pipefail
          ls -la
          test -f pom.xml
          test -f Dockerfile
          BASH
        ''')
      }
    }

    stage('Build Maven') {
      steps {
        sh(label: 'Maven package (skip tests compile)', script: '''
          bash <<'BASH'
          set -euo pipefail
          mvn -B clean package -Dmaven.test.skip=true
          ls -lh target/*.jar || true
          BASH
        ''')
      }
    }

    stage('SonarQube Scan') {
      steps {
        withSonarQubeEnv('sonar') {
          sh(label: 'Sonar scan', script: '''
            bash <<'BASH'
            set -euo pipefail

            echo "SONAR_HOST_URL=${SONAR_HOST_URL:-}"
            if [ -z "${SONAR_HOST_URL:-}" ]; then
              echo "ERROR: SONAR_HOST_URL is empty (check Jenkins Sonar config name 'sonar')"
              exit 1
            fi

            # Wait for Sonar to be UP (helps after restart)
            for i in {1..30}; do
              if curl -fsS --max-time 5 "${SONAR_HOST_URL}/api/system/status" | grep -q '"status":"UP"'; then
                echo "SonarQube is UP"
                break
              fi
              echo "Waiting for SonarQube... ($i/30)"
              sleep 5
            done

            mvn -B -Dmaven.test.skip=true sonar:sonar -Dsonar.projectKey="${SONAR_PROJECT_KEY}"
            BASH
          ''')
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
        sh(label: 'Docker check', script: '''
          bash <<'BASH'
          set -euo pipefail
          docker version
          docker info >/dev/null
          BASH
        ''')
      }
    }

    stage('Docker Build') {
      steps {
        sh(label: 'Docker build', script: '''
          bash <<'BASH'
          set -euo pipefail
          TAG_BUILD="${DOCKER_IMAGE}:${BUILD_NUMBER}"
          TAG_LATEST="${DOCKER_IMAGE}:latest"

          docker build -t "${TAG_BUILD}" -t "${TAG_LATEST}" .
          docker images | head -n 20
          BASH
        ''')
      }
    }

    stage('Docker Push (retry)') {
      when { expression { return params.PUSH_TO_DOCKERHUB } }
      steps {
        withCredentials([usernamePassword(credentialsId: DOCKER_CREDS_ID, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          timeout(time: 15, unit: 'MINUTES') {
            sh(label: 'Docker login + push with retries', script: '''
              bash <<'BASH'
              set -euo pipefail
              TAG_BUILD="${DOCKER_IMAGE}:${BUILD_NUMBER}"
              TAG_LATEST="${DOCKER_IMAGE}:latest"

              echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

              push_with_backoff () {
                local img="$1"
                local delays=(0 15 30 60 120 120)   # total ~6 min sleeps max
                local attempt=1
                for d in "${delays[@]}"; do
                  if [ "$d" -gt 0 ]; then
                    echo "Sleeping ${d}s before retry..."
                    sleep "$d"
                  fi
                  echo "Pushing $img (attempt ${attempt}/${#delays[@]})"
                  if docker push "$img"; then
                    echo "✅ Push OK: $img"
                    return 0
                  fi
                  echo "⚠️ Push failed: $img"
                  attempt=$((attempt+1))
                done
                echo "❌ Docker push failed after ${#delays[@]} attempts: $img"
                return 1
              }

              push_with_backoff "$TAG_BUILD"
              push_with_backoff "$TAG_LATEST"

              docker logout || true
              BASH
            ''')
          }
        }
      }
    }

    stage('Deploy to Minikube') {
      when { expression { return params.DEPLOY_TO_MINIKUBE } }
      steps {
        sh(label: 'kubectl apply', script: '''
          bash <<'BASH'
          set -euo pipefail

          if [ ! -f "$KUBECONFIG" ]; then
            echo "ERROR: KUBECONFIG not found at $KUBECONFIG"
            echo "Fix: copy vagrant kubeconfig to /var/lib/jenkins/.kube/config and chown jenkins:jenkins"
            exit 1
          fi

          export KUBECONFIG="$KUBECONFIG"

          kubectl get nodes

          kubectl get ns "$K8S_NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$K8S_NAMESPACE"

          if [ -d k8s ]; then
            kubectl apply -n "$K8S_NAMESPACE" -f k8s
          else
            YAMLS=$(ls *.yaml 2>/dev/null || true)
            [ -n "$YAMLS" ] || (echo "No k8s manifests found (k8s/ or *.yaml)" && exit 1)
            kubectl apply -n "$K8S_NAMESPACE" -f $YAMLS
          fi

          kubectl rollout status -n "$K8S_NAMESPACE" deploy/"$K8S_DEPLOYMENT" --timeout=180s
          BASH
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
