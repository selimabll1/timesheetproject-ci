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
    booleanParam(name: 'PUSH_TO_DOCKERHUB', defaultValue: false, description: 'Push to DockerHub (often fails with 502). For local Minikube, keep FALSE.')
    booleanParam(name: 'DEPLOY_TO_MINIKUBE', defaultValue: true, description: 'Deploy to Minikube (Minikube must already be running)')
  }

  environment {
    SONAR_PROJECT_KEY = 'timesheet-devops'
    DOCKER_IMAGE      = 'salima20033/timesheet-devops'
    DOCKER_CREDS_ID   = 'dockerhub-creds'

    K8S_NAMESPACE     = 'devops'
    K8S_DEPLOYMENT    = 'spring-app'   // change if different
    K8S_CONTAINER     = 'spring-app'   // change if container name differs
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Detect Project Files') {
      steps {
        sh(label: 'Detect', script: '''
          /bin/sh -e <<'SH'
          bash <<'BASH'
          set -euo pipefail
          ls -la
          test -f pom.xml
          test -f Dockerfile
          BASH
          SH
        ''')
      }
    }

    stage('Build Maven') {
      steps {
        sh(label: 'Maven package', script: '''
          /bin/sh -e <<'SH'
          bash <<'BASH'
          set -euo pipefail
          mvn -B clean package -Dmaven.test.skip=true
          ls -lh target/*.jar || true
          BASH
          SH
        ''')
      }
    }

    stage('SonarQube Scan') {
      when { expression { return params.RUN_SONAR } }
      steps {
        withSonarQubeEnv('sonar') {
          sh(label: 'Sonar scan', script: '''
            /bin/sh -e <<'SH'
            bash <<'BASH'
            set -euo pipefail

            echo "SONAR_HOST_URL=${SONAR_HOST_URL:-}"
            if [ -z "${SONAR_HOST_URL:-}" ]; then
              echo "ERROR: SONAR_HOST_URL empty (check Jenkins Sonar config name = 'sonar')"
              exit 1
            fi

            # wait for Sonar to be UP
            for i in $(seq 1 30); do
              if curl -fsS --max-time 5 "$SONAR_HOST_URL/api/system/status" | grep -q '"status":"UP"'; then
                echo "SonarQube is UP"
                break
              fi
              echo "Waiting for SonarQube... ($i/30)"
              sleep 5
            done

            mvn -B -Dmaven.test.skip=true sonar:sonar -Dsonar.projectKey="$SONAR_PROJECT_KEY"
            BASH
            SH
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

    stage('Docker Check') {
      steps {
        sh(label: 'Docker check', script: '''
          /bin/sh -e <<'SH'
          bash <<'BASH'
          set -euo pipefail
          docker version
          docker info >/dev/null
          BASH
          SH
        ''')
      }
    }

    stage('Docker Build') {
      steps {
        sh(label: 'Docker build', script: '''
          /bin/sh -e <<'SH'
          bash <<'BASH'
          set -euo pipefail
          docker build -t "${DOCKER_IMAGE}:${BUILD_NUMBER}" -t "${DOCKER_IMAGE}:latest" .
          BASH
          SH
        ''')
      }
    }

    stage('Docker Push (retry)') {
      when { expression { return params.PUSH_TO_DOCKERHUB } }
      steps {
        withCredentials([usernamePassword(credentialsId: DOCKER_CREDS_ID, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          timeout(time: 12, unit: 'MINUTES') {
            sh(label: 'Docker login + push', script: '''
              /bin/sh -e <<'SH'
              bash <<'BASH'
              set -euo pipefail

              echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

              push_retry () {
                local img="$1"
                local max=4
                local delay=10
                for attempt in $(seq 1 $max); do
                  echo "Pushing $img (attempt $attempt/$max)"
                  if docker push "$img"; then
                    echo "✅ Push OK: $img"
                    return 0
                  fi
                  echo "⚠️ Push failed: $img"
                  sleep "$delay"
                  delay=$((delay*2))
                  [ "$delay" -gt 60 ] && delay=60
                done
                echo "❌ Push failed after $max attempts: $img"
                return 1
              }

              push_retry "${DOCKER_IMAGE}:${BUILD_NUMBER}"
              push_retry "${DOCKER_IMAGE}:latest"

              docker logout || true
              BASH
              SH
            ''')
          }
        }
      }
    }

    stage('Deploy to Minikube') {
      when { expression { return params.DEPLOY_TO_MINIKUBE } }
      steps {
        sh(label: 'Deploy', script: '''
          /bin/sh -e <<'SH'
          bash <<'BASH'
          set -euo pipefail

          # Minikube must already be running
          minikube status

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

          # IMPORTANT for local minikube: avoid pulling from DockerHub
          # Set image to the build tag
          minikube kubectl -- -n "$K8S_NAMESPACE" set image deploy/"$K8S_DEPLOYMENT" "$K8S_CONTAINER"="${DOCKER_IMAGE}:${BUILD_NUMBER}"

          # (Optional but helpful) ensure it won't try to pull remotely
          minikube kubectl -- -n "$K8S_NAMESPACE" patch deploy "$K8S_DEPLOYMENT" --type='json' \
            -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]' || true

          minikube kubectl -- rollout status -n "$K8S_NAMESPACE" deploy/"$K8S_DEPLOYMENT" --timeout=180s
          BASH
          SH
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
