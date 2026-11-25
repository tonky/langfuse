package enact

_stages: [
	{
		name:      "checks"
		matrix:    true
		select:    [pipeline.#jobs.fmt, pipeline.#jobs.lint, pipeline.#jobs.typecheck, pipeline.#jobs.build, pipeline.#jobs.test]
		fail_fast: false
		services:  "on_demand"
	},
]
