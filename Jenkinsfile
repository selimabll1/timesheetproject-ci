stage('Docker Push') {
  steps {
    script {
      def pushOnce = { String img ->
        sh """#!/usr/bin/env bash
          set -euo pipefail
          echo "=== docker push ${img} ==="
          docker push "${img}" 2>&1 | tee "push-${env.BUILD_NUMBER}.log"
        """
      }

      def pushWithBackoff = { String img ->
        int maxAttempts = 6
        int sleepSec = 15
        for (int i = 1; i <= maxAttempts; i++) {
          echo "Pushing ${img} (attempt ${i}/${maxAttempts})"
          int rc = sh(script: """#!/usr/bin/env bash
            set -euo pipefail
            docker push "${img}" 2>&1 | tee "push-${env.BUILD_NUMBER}-${i}.log"
          """, returnStatus: true)

          if (rc == 0) { echo "✅ Pushed ${img}"; return }

          echo "❌ Push failed (rc=${rc}). Last lines:"
          sh """#!/usr/bin/env bash
            tail -n 60 "push-${env.BUILD_NUMBER}-${i}.log" || true
            echo "--- keywords ---"
            egrep -i "denied|unauthorized|forbidden|too many|429|502|timeout|i/o|EOF|TLS|connection|reset" "push-${env.BUILD_NUMBER}-${i}.log" || true
          """

          echo "⚠️ Sleeping ${sleepSec}s then retry..."
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
