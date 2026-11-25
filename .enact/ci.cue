package enact

pipeline: {
	ci: {
		concurrency: {
			max_parallel_jobs: 16
		}
		remote_cache: {
			secrets: {
				bucket:            "R2_BUCKET"
				access_key_id:     "R2_ACCESS_KEY_ID"
				secret_access_key: "R2_SECRET_ACCESS_KEY"
			}
			public_url: "https://cache.tonky.dev"
			public_key: "enve-r2-1:ckHPTeWVef6mba+1AwWHjKYCsUWKPfP9IXPm5YXNoHg="
			repo:       "tonky/langfuse"
			branch:     "main"
		}
		binaries: {
			// langfuse-speed v2: refresh cached enact-linux-x86_64 binary
			inputs: [".enact/ci.cue"]
			fetch: """
				set -euo pipefail
				mkdir -p bin/linux-x86_64
				base="https://github.com/tonky/langfuse/releases/download/enact-bin-langfuse"
				curl -fsSL "$base/enact-linux-x86_64" -o bin/linux-x86_64/enact
				curl -fsSL "$base/enve-linux-x86_64" -o bin/linux-x86_64/enve
				curl -fsSL "$base/enact-ebpf-loader-linux-x86_64" -o bin/linux-x86_64/enact-ebpf-loader
				chmod +x bin/linux-x86_64/enact bin/linux-x86_64/enve bin/linux-x86_64/enact-ebpf-loader
				"""
		}
		workers: {
			standard: {
				preset:          "github-public"
				labels: [
					"ubuntu-24.04",
				]
				tier:            "on_demand"
				available:       20
				cost_per_min:    0
				timeout_minutes: 60
			}
		}
	}
	workflows: {
		ci: {
			layout:   "staged"
			services: "on_demand"
			triggers: {
				push: branches: ["main"]
				pull_request: branches: ["main"]
			}
			stages: _stages
		}
	}
}
